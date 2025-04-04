{
  description = "PHP flake for Drupal development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs = inputs:

    inputs.flake-parts.lib.mkFlake {
      inherit inputs;
    } {
      systems = import inputs.systems;
      imports = [
        inputs.process-compose-flake.flakeModule
      ];

      perSystem = { self', pkgs, config, lib, ...}:
        let
          # Function to read env vars with defaults
          getEnvWithDefault = name: default:
            let
              envValue = builtins.getEnv name;
              envFileStr = builtins.readFile (toString ./.env);
              envFile = builtins.tryEval (
                if builtins.pathExists ./.env
                then builtins.listToAttrs (
                  builtins.map (line:
                    let pair = builtins.match "([^=]+)=(.*)" line;
                    in if pair == null then null
                      else { name = builtins.head pair; value = builtins.elemAt pair 1; }
                  ) (builtins.filter (line: line != "" && !(lib.hasPrefix "#" line))
                    (lib.splitString "\n" envFileStr))
                )
                else {}
              );
              envVars = if envFile.success then envFile.value
                else {};
            in
            if envValue != ""
              then envValue
              else if builtins.hasAttr name envVars
                then envVars.${name}
                else default;

          # Configuration with environment fallbacks
          projectName = getEnvWithDefault "PROJECT_NAME" "drupal-demo";
          domain = getEnvWithDefault "DOMAIN" "${projectName}.ddev.site";
          port = getEnvWithDefault "PORT" "8088";
          phpVersion = getEnvWithDefault "PHP_VERSION" "php83";
          drupalPackage = getEnvWithDefault "DRUPAL_PACKAGE" "drupal/cms";
          docroot = getEnvWithDefault "DOCROOT" "web";

          inherit (inputs.services-flake.lib) multiService;

          baseConfig ={
            imports = [
              inputs.services-flake.processComposeModules.default
              # (multiService ./.services/caddy.nix)
              (multiService ./.services/phpfpm.nix)
              (multiService ./.services/init.nix)
              (multiService ./.services/nix-settings.nix)
            ];

            services.mysql."${projectName}-db" = {
              enable = true;
              settings.mysqld = {
                # Optional: Set other MySQL settings
                # port = 3307;
                # bind_address = "127.0.0.1";
                skip_grant_tables = true;
                skip_networking = true;
                transaction_isolation = "READ-COMMITTED";
              };
              initialDatabases = [
                {
                  name = "drupal"; # Database name
                }
              ];

            };
            services.phpfpm."${projectName}-php" = {
              enable = true;
              # Override PHP version:
              phpVersion = phpVersion;
            };
            # Create log dir
            settings.processes.setupNginx = {
              command = ''
                mkdir -p logs
              '';
            };
            services.nginx."${projectName}-nginx" = {
              enable = true;

	      # Without this Nginx always claims port 8080, and can't be started elsewhere.
	      port = lib.strings.toInt port;
              # Override domain:
              httpConfig = ''
                server {
                  listen ${port};
                  server_name ${domain};
                  root ${docroot};
                  index index.php index.html index.htm;

                  # logging
                  access_log logs/${projectName}-access.log;
                  error_log logs/${projectName}-error.log;

                  location / {
                    try_files $uri $uri/ /index.php?$query_string;
                  }

                  location ~ \.php$ {
                    fastcgi_split_path_info ^(.+\.php)(/.+)$;
                    fastcgi_pass unix:/tmp/${projectName}-php.sock;
                    fastcgi_index index.php;
                    include ${pkgs.nginx}/conf/fastcgi_params;

                    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                    fastcgi_param PATH_INFO $fastcgi_path_info;
                    fastcgi_param QUERY_STRING $query_string;
                    fastcgi_intercept_errors on;
		    # Set read timeout to an hour, for debugging
                    fastcgi_read_timeout 3600;
		    # Drupal sends big headers in dev mode, need to increase buffer size
                    fastcgi_buffer_size 128k;
                    fastcgi_buffers 4 256k;
                    fastcgi_busy_buffers_size 256k;
                  }

                  # Deny access to . files
                  location ~ /\. {
                    deny all;
                  }

                  # Allow fpm ping and status
                  location ~ ^/(fpm-status|fpm-ping)$ {
                    access_log off;
                    allow 127.0.0.1;
                    deny all;
                    fastcgi_pass unix:data/php/php-fpm.sock;
                    include ${pkgs.nginx}/conf/fastcgi_params;
                  }

                }
              '';
            };
            #services.caddy."${projectName}" = {
            #  enable = true;
              # Override domain:
            #  settings.domain = domain;
            #};
            services.nix-settings."nix-settings" = {
              enable = true;
              # Set the project name
              projectName = projectName;
              # Set the domain
              domain = domain;
              # Set the port
              port = port;
              # Set the docroot
              docroot = docroot;
            };


            # Open browser to the domain
            settings.processes.open-browser = {
              command = ''
                sleep 2
                xdg-open http://${domain}:${port}
              '';
              depends_on."${projectName}-nginx".condition = "process_healthy";
            };
          };

      in
      {
        process-compose."default" = { config, ...}: baseConfig;

        # New demo target to install Drupal
        process-compose."demo" = { config, ...}:
          lib.recursiveUpdate baseConfig {
            services.init."cms" = {
              enable = true;
              projectName = projectName;
              drupalPackage = drupalPackage;
              #php = baseConfig.services.phpfpm."${projectName}-php".settings.php;
              # mysqlDataDir = mysqlDataDir; # /. + "/data/${projectName}-db";
              # php = baseConfig.settings.processes."${projectName}-php".default;
            };
            settings.processes.cms = {
              readiness_probe = {
                # Check if Drupal is installed
                exec.command = "test -f web/index.php";
                initial_delay_seconds = 1;
                period_seconds = 3;
                timeout_seconds = 1;
                success_threshold = 1;
                failure_threshold = 60;
              };
              availability = {
                restart = "no";
              };
            };

            # Make other services depend on the Drupal installation
            settings.processes."nix-settings".depends_on.cms.condition = "process_completed_successfully";
            settings.processes."${projectName}-php".depends_on.cms.condition = "process_completed_successfully";
            settings.processes."${projectName}-nginx".depends_on.cms.condition = "process_completed_successfully";
          };


        # Dev shell for debugging
        devShells.default = pkgs.mkShellNoCC {
          inputsFrom = [
            config.process-compose."default".services.outputs.devShell
          ];
          # Adds a "demo" command to start the demo scripts
          nativeBuildInputs = [
            self'.packages.demo
          ];
          buildInputs = with pkgs; [
            (writeScriptBin "nix-settings" (builtins.readFile ./.services/bin/nix-settings))
            (writeScriptBin "refresh-flake" (builtins.readFile ./.services/bin/refresh-flake))
            (writeScriptBin "xdrush" ''
              #!${pkgs.bash}/bin/bash
              php -d xdebug.mode=debug \
                -d xdebug.start_with_request=yes \
                -d xdebug.client_host=localhost \
                -d xdebug.client_port=9003 \
                $PROJECT_ROOT/vendor/bin/drush.php "$@"
            '')
          ];
          DRUSH_OPTIONS_URI = "http://${domain}:${port}";

          shellHook = ''
            export PROJECT_ROOT="$PWD"
            echo "Entering development environment for ${projectName}"
            echo "Use nix run to start everything up, and then use a different shell for management. You can import a database using drush sqlc < db.sql"
          '';
        };
      };
    };
  }
