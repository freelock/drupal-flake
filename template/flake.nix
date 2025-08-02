{
  description = "PHP flake for Drupal development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-php74.url = "github:NixOS/nixpkgs/6e3a86f2f73a466656a401302d3ece26fba401d9";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake/8bc6dff1c0d82842b28e3906ac4645a3c3a49dbe";
  };

  outputs = inputs:

    inputs.flake-parts.lib.mkFlake {
      inherit inputs;
    } {
      systems = import inputs.systems;
      imports = [
        inputs.process-compose-flake.flakeModule
      ];

      perSystem = { self', pkgs, config, lib, system, ...}:
        let
          # Add nixpkgs-php74 for PHP 7.4 support
          pkgs-php74 = import inputs.nixpkgs-php74 { inherit system; };

          # Load local extensions if available
          localExtensions =
            if builtins.pathExists ./nix/local-extensions.nix
            then import ./nix/local-extensions.nix { inherit pkgs lib system; }
            else {
              extraPhpExtensions = [];
              extraNixPackages = [];
              customTools = [];
            };

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
          # Get the appropriate package set based on PHP version
          phpPkgs = if phpVersion == "php74" then pkgs-php74 else pkgs;
          drupalPackage = getEnvWithDefault "DRUPAL_PACKAGE" "drupal/cms";
          phpTimeout = lib.strings.toInt (getEnvWithDefault "PHP_TIMEOUT" "60");
          docroot = getEnvWithDefault "DOCROOT" "web";
          # Calculate the relative path from docroot to project root
          projectRoot =
            if docroot == "." then "."
            else if builtins.match "^[^/]+$" docroot != null then "../"
            else "../" + builtins.concatStringsSep "" (builtins.genList (i: "../") (
              (builtins.length (builtins.filter (x: x != "") (lib.splitString "/" docroot))) - 1
            ));
          # TODO: figure out how to make this an absolute path, primarily for php-fpm.
          dbSocket = getEnvWithDefault "DB_SOCKET" "data/${projectName}-db/mysql.sock";

          inherit (inputs.services-flake.lib) multiService;

          # Create a final combined pkgs that includes both package sets
          # This allows us to use either the standard nixpkgs or the php74 version
          finalPkgs = pkgs // {
            php74 = pkgs-php74.php74;
            drush = pkgs-php74.drush;
          };

          baseConfig = {
            imports = [
              inputs.services-flake.processComposeModules.default
              # (multiService ./.services/caddy.nix)
              (multiService ./.services/phpfpm.nix)
              (multiService ./.services/init.nix)
              (multiService ./.services/config.nix)
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
              # Pass the appropriate package set based on PHP version
              pkgs = finalPkgs;
              # TODO: This currently should have ${PWD}/ prefixing it, so this is currently wrong.
              dbSocket = dbSocket;
              # Pass extra PHP extensions from local extensions
              extraPhpExtensions = localExtensions.extraPhpExtensions or [];
              # Set PHP timeout
              phpTimeout = phpTimeout;
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
                  access_log data/${projectName}-nginx/${projectName}-access.log;
                  error_log data/${projectName}-nginx/${projectName}-error.log;

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
              # Set the project root relative path
              projectRoot = projectRoot;
              # Set the MySQL socket path
              dbSocket = dbSocket;
            };


          }
          // lib.optionalAttrs (builtins.getEnv "CI" == "" && builtins.getEnv "GITLAB_CI" == "" && builtins.getEnv "GITHUB_ACTIONS" == "") {
            # Open browser to the domain (only if not in CI environment)
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
        process-compose."default" = { config, ...}: baseConfig // {
          # Override process-compose CLI options
          cli.options = {
            # Enable REST server on port 8080 instead of disabling it
            no-server = false;
            # Use Unix domain socket (path set via PC_SOCKET_PATH env var)
            use-uds = true;
          };

          # Create status file when process-compose starts
          settings.processes.pc-status-start = {
            command = "echo '${projectName}' > /tmp/pc-running-${projectName}";
            availability.restart = "no";
          };
        };

        # Detached target - same as default but runs in background
        process-compose."detached" = { config, ...}: baseConfig // {
          # Override process-compose CLI options
          cli.options = {
            # Enable REST server on port 8080 instead of disabling it
            no-server = false;
            # Use Unix domain socket (path set via PC_SOCKET_PATH env var)
            use-uds = true;
          };
        };

        # New demo target to install Drupal
        process-compose."demo" = { config, ...}:
          lib.recursiveUpdate baseConfig {
            # Override process-compose CLI options
            cli.options = {
              # Enable REST server on port 8080 instead of disabling it
              no-server = false;
              # Use Unix domain socket (path set via PC_SOCKET_PATH env var)
              use-uds = true;
            };
            services.init."cms" = {
              enable = true;
              projectName = projectName;
              drupalPackage = drupalPackage;
              dbSocket = dbSocket;
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

        # Config target to install drupal from config
        process-compose."config" = { config, ...}:
          lib.recursiveUpdate baseConfig {
            # Override process-compose CLI options
            cli.options = {
              # Enable REST server on port 8080 instead of disabling it
              no-server = false;
              # Use Unix domain socket (path set via PC_SOCKET_PATH env var)
              use-uds = true;
            };
            services.config."cms" = {
              enable = true;
              projectName = projectName;
            };
            settings.processes.cms = {
              depends_on = {
                "nix-settings" = {
                  condition = "process_completed_successfully";
                };
              };
              availability = {
                restart = "no";
              };
            };

            # Make other services depend on the Drupal installation
            #settings.processes."nix-settings".depends_on.cms.condition = "process_completed_successfully";
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
            (pkgs.writeScriptBin "start-config" ''
              #!${pkgs.bash}/bin/bash
              nix run .#config
            '')
            (pkgs.writeScriptBin "start-demo" ''
              #!${pkgs.bash}/bin/bash
              nix run .#demo
            '')
            (pkgs.writeScriptBin "start" ''
              #!${pkgs.bash}/bin/bash
              nix run
            '')
            (pkgs.writeScriptBin "start-detached" ''
              #!${pkgs.bash}/bin/bash
              echo "🚀 Starting ${projectName} development environment in detached mode..."

              # Use setsid to properly detach the process while keeping server functionality
              mkdir -p ./data
              setsid nix run . -- --tui=false </dev/null >./data/process-compose.log 2>&1 &
              COMPOSE_PID=$!
              sleep 5

              # Check if process is still running
              if kill -0 $COMPOSE_PID 2>/dev/null; then
                echo "✅ Development environment started in background (PID: $COMPOSE_PID)"
                echo "   Use 'pc-stop' to stop the services"
                echo "   View process logs: tail -f ./data/process-compose.log"
                echo "   Check status: pgrep -f ${projectName}"
                echo "   Site URL: http://${domain}:${port}"
                echo "   Process logs: ./data/process-compose.log"
                echo "   Nginx logs: ./data/${projectName}-nginx/"
              else
                echo "❌ Failed to start development environment"
                echo "   Check process logs: ./data/process-compose.log"
                exit 1
              fi
            '')
            (pkgs.writeScriptBin "pc-stop" ''
              #!${pkgs.bash}/bin/bash
              echo "🛑 Stopping ${projectName} development environment..."

              # Use the socket to stop this specific project
              if [ -n "''${PC_SOCKET_PATH:-}" ] && [ -e "''${PC_SOCKET_PATH}" ]; then
                echo "   Stopping via socket: ''${PC_SOCKET_PATH}"
                process-compose down || true
                echo "✅ ${projectName} development environment stopped"
              else
                echo "ℹ️  ${projectName} development environment is not running"
              fi
            '')
            # Legacy alias for backward compatibility
            (pkgs.writeScriptBin "stop-detached" ''
              #!${pkgs.bash}/bin/bash
              echo "⚠️  'stop-detached' is deprecated, use 'pc-stop' instead"
              pc-stop "$@"
            '')
            (pkgs.writeScriptBin "stop-all" ''
              #!${pkgs.bash}/bin/bash
              echo "🛑 Stopping ALL process-compose development environments..."

              # Find all process-compose processes and stop them
              if pgrep -f "process-compose" >/dev/null 2>&1; then
                echo "   Found running process-compose instances, stopping them..."
                pkill -f "process-compose" || true
                sleep 2

                # Clean up any remaining processes
                pkill -f "process-compose" -9 || true

                # Clean up status files
                rm -f /tmp/pc-running-* 2>/dev/null || true

                echo "✅ All development environments stopped"
              else
                echo "ℹ️  No process-compose instances found"
              fi
            '')
          ];
          buildInputs = with pkgs; [
            # Add process-compose for attach command
            process-compose
            (writeScriptBin "nix-settings" (builtins.readFile ./.services/bin/nix-settings))
            (writeScriptBin "refresh-flake" (builtins.readFile ./.services/bin/refresh-flake))
            (writeScriptBin "setup-starship-prompt" (builtins.readFile ./.services/bin/setup-starship-prompt))
            (writeScriptBin "xdrush" ''
              #!${pkgs.bash}/bin/bash
              # Create logs directory if it doesn't exist
              mkdir -p $PROJECT_ROOT/data/logs
              mkdir -p $PROJECT_ROOT/data/xdebug_profiles

              if [ "${phpVersion}" = "php74" ] && [ -e ${finalPkgs.drush or ""}/bin/drush ]; then
                # Use standalone drush with PHP 7.4
                php -d xdebug.mode=debug \
                  -d xdebug.start_with_request=yes \
                  -d xdebug.client_host=localhost \
                  -d xdebug.client_port=9003 \
                  ${finalPkgs.drush}/bin/drush "$@"
              else
                # Use vendor/bin/drush.php with other PHP versions
                php -d xdebug.mode=debug \
                  -d xdebug.start_with_request=yes \
                  -d xdebug.client_host=localhost \
                  -d xdebug.client_port=9003 \
                  $PROJECT_ROOT/vendor/bin/drush.php "$@"
              fi
            '')
            (writeScriptBin "xdebug-profile-on" ''
              #!${pkgs.bash}/bin/bash
              echo "⚠️  XDebug profiling requires manual configuration."
              echo "   To enable profiling, you can:"
              echo "   1. Add ?XDEBUG_PROFILE=1 to your URL for individual requests"
              echo "   2. Set cookie XDEBUG_PROFILE=1 in your browser"
              echo "   3. Use environment variable: export XDEBUG_MODE=debug,profile"
              echo ""
              echo "   Profiles will be saved to: data/xdebug_profiles/"
              echo "   Current xdebug.mode: debug (for debugging)"
            '')
            (writeScriptBin "xdebug-profile-off" ''
              #!${pkgs.bash}/bin/bash
              echo "ℹ️  XDebug profiling is controlled per-request."
              echo "   Remove ?XDEBUG_PROFILE=1 from URLs or XDEBUG_PROFILE cookie to disable."
            '')
            (writeScriptBin "pc-status" ''
              #!${pkgs.bash}/bin/bash
              SOCKET="''${PC_SOCKET_PATH:-/tmp/process-compose-${projectName}.sock}"
              if [ -S "$SOCKET" ]; then
                echo "🟢 Process-compose is running"
                echo "   Socket: $SOCKET"
                echo "   Project: ${projectName}"

                # Try to get status via API
                if command -v curl >/dev/null 2>&1; then
                  echo ""
                  echo "API Status:"
                  curl --silent --max-time 2 --unix-socket "$SOCKET" http://localhost/project/state | \
                    ${pkgs.jq}/bin/jq -r '  "   Uptime: " + (.upTime/1000000000 | floor | tostring) + "s" +
                                            "\n   Processes: " + (.runningProcessNum | tostring) + "/" + (.processNum | tostring) + " running" +
                                            "\n   Version: " + .version' 2>/dev/null || echo "   API unavailable"
                fi
              else
                echo "🔴 Process-compose is not running"
                echo "   Expected socket: $SOCKET"
              fi
            '')
            (writeScriptBin "pc-attach" ''
              #!${pkgs.bash}/bin/bash
              if [ -n "''${PC_SOCKET_PATH:-}" ]; then
                echo "🔗 Attaching to process-compose TUI..."
                # process-compose attach will use PC_SOCKET_PATH automatically
                process-compose attach
              else
                echo "❌ PC_SOCKET_PATH not set"
                echo "   Are you in the development shell? Try 'nix develop'"
                exit 1
              fi
            '')
            (writeScriptBin "starship-process-compose" ''
              #!${pkgs.bash}/bin/bash
              # Ultra-fast starship module

              # Quick exit if not in nix environment
              [ -n "''${PROJECT_NAME:-}" ] || exit 1
              [ -n "''${PC_SOCKET_PATH:-}" ] || exit 1

              # Just check if socket file exists (faster than socket test)
              [ -e "''${PC_SOCKET_PATH}" ] && echo "💧❄️ ''${PROJECT_NAME}" || exit 1
            '')
            (writeScriptBin "?" ''
              #!${pkgs.bash}/bin/bash
              echo -e "\n\033[1;34m${projectName} Development Commands:\033[0m"
              echo -e "\033[1;32mnix run\033[0m                 Start the development environment"
              echo -e "\033[1;32mstart\033[0m                   Start the development environment"
              echo -e "\033[1;32mstart-detached\033[0m          Start the development environment in background"
              echo -e "\033[1;32mpc-stop\033[0m                 Stop the current project's development environment"
              echo -e "\033[1;32mstop-all\033[0m                Stop ALL process-compose development environments"
              echo -e "\033[1;32mnix run .#demo\033[0m          Set up a new Drupal site, or start servers"
              echo -e "\033[1;32mstart-demo\033[0m              Set up a new Drupal site, or start servers"
              echo -e "\033[1;32mstart-config\033[0m            Start servers and install Drupal from config - CLOBBERS EXISTING DATABASE"
              echo -e "\033[1;32mpc-status\033[0m               Check process-compose status and socket"
              echo -e "\033[1;32mpc-attach\033[0m               Attach to running process-compose TUI"
              echo -e "\033[1;32mxdrush\033[0m                  Run Drush with Xdebug enabled"
              echo -e "\033[1;32mxdebug-profile-on\033[0m       Enable XDebug profiling (requires restart)"
              echo -e "\033[1;32mxdebug-profile-off\033[0m      Disable XDebug profiling (requires restart)"
              echo -e "\033[1;32mnix-settings\033[0m            Add/include settings.nix.php (done automatically with start)"
              echo -e "\033[1;32mrefresh-flake [path]\033[0m    Refresh the flake from Drupal.org or [path]"
              echo -e "\033[1;32msetup-starship-prompt\033[0m   Set up starship prompt to show process-compose status"
              echo -e "\033[1;32m?\033[0m                       Show this help message"
              echo ""
              echo -e "Site URL: \033[1;33mhttp://${domain}:${port}\033[0m"
              echo -e "Socket: \033[1;33m''${PC_SOCKET_PATH:-/tmp/process-compose-${projectName}.sock}\033[0m"
            '')
          ] ++ (localExtensions.extraNixPackages or []) ++ (localExtensions.customTools or []);
          DRUSH_OPTIONS_URI = "http://${domain}:${port}";

          shellHook = ''
            export PROJECT_ROOT="$PWD"
            export PROJECT_ROOT_REL="${projectRoot}"
            export PROJECT_NAME="${projectName}"
            export PATH="$PWD/vendor/bin:$PATH"
            export DB_SOCKET="$PWD/${dbSocket}"
            export PC_SOCKET_PATH="/tmp/process-compose-${projectName}.sock"
            export PROCESS_COMPOSE_SOCKET="$PC_SOCKET_PATH"  # Backward compatibility
            export PC_STATUS_FILE="/tmp/pc-running-${projectName}"
            echo "Entering development environment for ${projectName}"
            echo "Use '?' to see the commands provided in this flake."
          '';
        };
      };
    };
  }
