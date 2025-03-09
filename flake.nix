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
          projectName = "drupal-demo";
          domain = "${projectName}.ddev.site";
          port = "8088";
          mysqlDataDir = "/home/john/git/drupal-flake/data/${projectName}-db";
          inherit (inputs.services-flake.lib) multiService;


          baseConfig ={
            imports = [
              inputs.services-flake.processComposeModules.default
              # (multiService ./.services/caddy.nix)
              (multiService ./.services/phpfpm.nix)
            ];
            services.mysql."${projectName}-db" = {
              enable = true;
              settings.mysqld = {
                # Optional: Set other MySQL settings
                # port = 3307;
                # bind_address = "127.0.0.1";
                skip_grant_tables = true;
                skip_networking = true;
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
              #settings.phpfpm.package = pkgs.php83;
            };
            # Create log dir
            settings.processes.setupNginx = {
              command = ''
                mkdir -p logs
              '';
            };
            services.nginx."${projectName}-nginx" = {
              enable = true;
              # Override domain:
              httpConfig = ''
                server {
                  listen ${port};
                  server_name ${domain};
                  root web;
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
            settings.processes.init = {
              command = ''
                if [ ! -f "web/index.php" ]; then
                  echo "Installing Drupal CMS..."
                  composer create-project drupal/cms cms
                  mv cms/* ./
                  mv cms/.* ./
                  rmdir cms
                  composer install

                  # Copy settings file without comments and enable local settings include
                  grep -v '^#' web/sites/default/default.settings.php | grep -v '^/\*' | grep -v '^ \*' | grep -v '^ \*/' > web/sites/default/settings.php
                  echo 'if (file_exists($$app_root . "/" . $$site_path . "/settings.local.php")) {' >> web/sites/default/settings.php
                  echo '  include $$app_root . "/" . $$site_path . "/settings.local.php";' >> web/sites/default/settings.php
                  echo "}" >> web/sites/default/settings.php

                  mkdir -p web/sites/default/files
                  chmod 777 web/sites/default/settings.php
                  chmod 777 web/sites/default
                fi
                # Create local settings with database configuration
                cat > web/sites/default/settings.local.php << 'EOL'
                <?php
                $$databases['default']['default'] = [
                  'database' => 'drupal',
                  'username' => "drupal",
                  'password' => "",
                  'host' => 'localhost',
                  'unix_socket' => '${mysqlDataDir}/mysql.sock',
                  'driver' => 'mysql',
                  'prefix' => "",
                ];

                $$settings['hash_salt'] = 'development-only-hash';
                $$settings['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';
                $$settings['cache']['bins']['render'] = 'cache.backend.null';
                $$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';
                $$settings['cache']['bins']['page'] = 'cache.backend.null';
                $$config['system.performance']['css']['preprocess'] = FALSE;
                $$config['system.performance']['js']['preprocess'] = FALSE;
                EOL

                # Include local settings in main settings.php if not already included
                if ! grep -q "settings.local.php" web/sites/default/settings.php; then
                  echo "include $$app_root . '/' . $$site_path . '/settings.local.php';" >> web/sites/default/settings.php
                fi

                chmod 777 web/sites/default/settings.local.php

                # Skip perms hardening, set config directory
                echo '$$settings["skip_permissions_hardening"] = TRUE;' >> web/sites/default/settings.php
                echo '$$config_directories["sync"] = "../config";' >> web/sites/default/settings.php

                # Back up settings.php - drush site:install incorrectly adds $databases to settings.php
                cp web/sites/default/settings.php web/sites/default/settings.php.tmp

                drush site:install -y

                # Restore settings.php
                mv web/sites/default/settings.php.tmp web/sites/default/settings.php
              '';

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
            settings.processes."${projectName}-php".depends_on.init.condition = "process_completed_successfully";
            settings.processes."${projectName}-nginx".depends_on.init.condition = "process_completed_successfully";
          };

        devShells.default = pkgs.mkShell {
          inputsFrom = [
            config.process-compose."default".services.outputs.devShell

          ];

        };
      };
    };
  }
