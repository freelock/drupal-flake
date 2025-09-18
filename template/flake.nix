{
  description = "PHP flake for Drupal development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-php74.url = "github:NixOS/nixpkgs/6e3a86f2f73a466656a401302d3ece26fba401d9";
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
              extraPaths = [];
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
          # Use relative path, but php-fpm.nix should handle the absolute path conversion
          dbSocket = getEnvWithDefault "DB_SOCKET" "data/${projectName}-db/mysql.sock";

          inherit (inputs.services-flake.lib) multiService;

          # Create a final combined pkgs that includes both package sets
          # This allows us to use either the standard nixpkgs or the php74 version
          finalPkgs = pkgs // {
            php74 = pkgs-php74.php74;
          } // (lib.optionalAttrs (pkgs-php74 ? drush) {
            drush = pkgs-php74.drush;
          });

          baseConfig = {
            imports = [
              inputs.services-flake.processComposeModules.default
              # (multiService ./.services/caddy.nix)
              (multiService ./.services/php-fpm.nix)
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
            services.php-fpm."${projectName}-php" = {
              enable = true;
              # Override PHP version:
              phpVersion = phpVersion;
              # Pass the appropriate package set based on PHP version
              pkgs = finalPkgs;
              # TODO: This currently should have ${PWD}/ prefixing it, so this is currently wrong.
              dbSocket = dbSocket;
              # Pass extra PHP extensions from local extensions
              extraPhpExtensions = localExtensions.extraPhpExtensions or [];
              # Pass extra paths from local extensions
              extraPaths = localExtensions.extraPaths or [];
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
                  server_name ${domain} localhost 127.0.0.1;
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

        # Demo package that wraps process-compose demo with argument parsing
        packages.demo = pkgs.writeScriptBin "demo" ''
          #!${pkgs.bash}/bin/bash
          
          # Default values
          DRUPAL_PACKAGE="drupal/cms"
          PROJECT_NAME=""
          COMPOSER_OPTIONS=""
          DETACHED_MODE=false
          
          # Parse flags first
          while [ $# -gt 0 ]; do
            case "$1" in
              --help|-h)
                echo "Usage: nix run .#demo [-- [--detached|--no-tui] [DRUPAL_PACKAGE] [PROJECT_NAME] [COMPOSER_OPTIONS]]"
                echo ""
                echo "Flags:"
                echo "  --detached, --no-tui  Run without TUI (for CI/testing)"
                echo ""
                echo "Arguments:"
                echo "  DRUPAL_PACKAGE   Drupal package to install (default: drupal/cms)"
                echo "                   Examples: drupal/cms, drupal/recommended-project, phenaproxima/xb-demo"
                echo "  PROJECT_NAME     Custom project name (default: drupal-demo)"
                echo "                   If provided, creates .env file with this name"
                echo "  COMPOSER_OPTIONS Additional composer create-project options"
                echo "                   Example: --stability=dev"
                echo ""
                echo "Examples:"
                echo "  nix run .#demo                                            # Use defaults"
                echo "  nix run .#demo -- --detached                             # Run without TUI"
                echo "  nix run .#demo -- phenaproxima/xb-demo                   # Install XB demo"
                echo "  nix run .#demo -- phenaproxima/xb-demo my-project        # With custom name"
                echo "  nix run .#demo -- --detached phenaproxima/xb-demo my-project --stability=dev"
                exit 0
                ;;
              --detached|--no-tui)
                DETACHED_MODE=true
                shift
                ;;
              *)
                break
                ;;
            esac
          done
          
          # Parse positional arguments
          if [ -n "''${1:-}" ]; then
            DRUPAL_PACKAGE="$1"
          fi
          if [ -n "''${2:-}" ]; then
            PROJECT_NAME="$2"
          fi
          # Handle composer options (may have multiple arguments)
          if [ $# -gt 2 ]; then
            shift 2
            COMPOSER_OPTIONS="$*"
          fi
          
          # Determine effective project name
          EFFECTIVE_PROJECT_NAME="''${PROJECT_NAME:-${projectName}}"
          
          echo "Starting demo with:"
          echo "  Package: $DRUPAL_PACKAGE"  
          echo "  Project Name: $EFFECTIVE_PROJECT_NAME"
          echo "  Composer Options: ''${COMPOSER_OPTIONS:-none}"
          echo ""
          
          # Create .env file if custom project name is provided  
          if [ -n "$PROJECT_NAME" ] && [ ! -f ".env" ]; then
            echo "Creating .env file with custom project name: $PROJECT_NAME"
            if [ -f ".env.example" ]; then
              cp .env.example .env
              ${pkgs.gnused}/bin/sed -i "s/^# PROJECT_NAME=.*/PROJECT_NAME=$PROJECT_NAME/" .env
            else
              # For remote flakes, create a basic .env file
              echo "PROJECT_NAME=$PROJECT_NAME" > .env
              echo "DOMAIN=$EFFECTIVE_PROJECT_NAME.ddev.site" >> .env  
              echo "PORT=${port}" >> .env
              echo "DOCROOT=web" >> .env
            fi
          fi
          
          # Override environment variables for this run
          export PROJECT_NAME="$EFFECTIVE_PROJECT_NAME"
          export DOMAIN="$EFFECTIVE_PROJECT_NAME.ddev.site"
          export DOCROOT="web"
          export DEMO_DRUPAL_PACKAGE="$DRUPAL_PACKAGE"
          export DEMO_COMPOSER_OPTIONS="$COMPOSER_OPTIONS"
          
          # Set detached mode environment variable for demo-static to use
          if [ "$DETACHED_MODE" = "true" ]; then
            echo "Starting in detached/no-TUI mode..."
            export DEMO_DETACHED_MODE=true
          fi
          
          # Run the demo-static directly - it will use the exported variables
          ${self'.packages.demo-static}/bin/demo-static
        '';

        # Wrapper for demo-static that can handle detached mode
        packages.demo-static = pkgs.writeScriptBin "demo-static" ''
          #!${pkgs.bash}/bin/bash
          
          # Get the actual demo-static-internal binary
          DEMO_STATIC_BIN="${self'.packages.demo-static-internal}/bin/demo-static-internal"
          
          # If DEMO_DETACHED_MODE is set, run in background with --tui=false
          if [ "''${DEMO_DETACHED_MODE:-}" = "true" ]; then
            echo "Starting demo in detached mode..."
            
            # Create a modified version that adds --tui=false, then run detached
            TEMP_WRAPPER=$(mktemp)
            trap "rm -f $TEMP_WRAPPER" EXIT
            
            # Copy the original script and add --tui=false
            ${pkgs.gnused}/bin/sed 's/process-compose --use-uds/process-compose --tui=false --use-uds/g' "$DEMO_STATIC_BIN" > "$TEMP_WRAPPER"
            chmod +x "$TEMP_WRAPPER"
            
            # Run the modified script in background using setsid to properly detach
            mkdir -p ./data
            setsid "$TEMP_WRAPPER" "$@" </dev/null >./data/demo-detached.log 2>&1 &
            PC_PID=$!
            
            sleep 3  # Give it time to start
            
            # Check if process is still running
            if kill -0 $PC_PID 2>/dev/null; then
              echo "✅ Demo started in background (PID: $PC_PID)"
              echo "   Check logs: ./data/demo-detached.log"
              echo "   Use 'kill $PC_PID' to stop"
            else
              echo "❌ Failed to start demo in background"
              echo "   Check logs: ./data/demo-detached.log"
              exit 1
            fi
          else
            # Run the original script
            exec "$DEMO_STATIC_BIN" "$@"
          fi
        '';

        # Static demo process-compose (the original functionality) 
        process-compose."demo-static-internal" = { config, ...}:
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
              composerOptions = "";
              customProjectName = "";
              dbSocket = dbSocket;
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
        devShells.default = 
          let
            # Prepare local extension packages safely
            localPackages = (localExtensions.extraNixPackages or []) ++ (localExtensions.customTools or []);
          in
          pkgs.mkShellNoCC {
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
              
              # Show usage if help requested
              if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
                echo "Usage: start-demo [DRUPAL_PACKAGE] [PROJECT_NAME] [COMPOSER_OPTIONS]"
                echo ""
                echo "Arguments:"
                echo "  DRUPAL_PACKAGE   Drupal package to install (default: drupal/cms)"
                echo "                   Examples: drupal/cms, drupal/recommended-project, phenaproxima/xb-demo"
                echo "  PROJECT_NAME     Custom project name (default: drupal-demo)"
                echo "                   If provided, creates .env file with this name"
                echo "  COMPOSER_OPTIONS Additional composer create-project options"
                echo "                   Example: --stability=dev"
                echo ""
                echo "Examples:"
                echo "  start-demo                                    # Use defaults"
                echo "  start-demo phenaproxima/xb-demo              # Install XB demo"
                echo "  start-demo phenaproxima/xb-demo my-project   # With custom name"
                echo "  start-demo phenaproxima/xb-demo my-project --stability=dev"
                echo ""
                echo "Equivalent nix run commands:"
                echo "  nix run .#demo                                # Use defaults"
                echo "  nix run .#demo -- phenaproxima/xb-demo       # Install XB demo"
                echo "  nix run .#demo -- phenaproxima/xb-demo my-project --stability=dev"
                exit 0
              fi
              
              # Pass all arguments to nix run .#demo after --
              if [ $# -gt 0 ]; then
                nix run .#demo -- "$@"
              else
                nix run .#demo
              fi
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
              
              # In CI environments, add additional process-compose options for resource efficiency
              COMPOSE_ARGS="--tui=false"
              if [ -n "''${CI:-}" ] || [ -n "''${GITLAB_CI:-}" ] || [ -n "''${GITHUB_ACTIONS:-}" ]; then
                echo "   Running in CI mode with reduced resource usage"
                COMPOSE_ARGS="$COMPOSE_ARGS --disable-healthcheck=false --log-level=info"
              fi
              
              setsid nix run . -- $COMPOSE_ARGS </dev/null >./data/process-compose.log 2>&1 &
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
          buildInputs = (with pkgs; [
            # Add process-compose for attach command
            process-compose
            (writeScriptBin "nix-settings" (builtins.readFile ./.services/bin/nix-settings))
            (writeScriptBin "refresh-flake" (builtins.readFile ./.services/bin/refresh-flake))
            (writeScriptBin "setup-starship-prompt" (builtins.readFile ./.services/bin/setup-starship-prompt))
            (writeScriptBin "phpunit-setup" (builtins.readFile ./.services/bin/phpunit-setup))
            (writeScriptBin "phpunit-module" (builtins.readFile ./.services/bin/phpunit-module))
            (writeScriptBin "phpunit-custom" (builtins.readFile ./.services/bin/phpunit-custom))
            (writeScriptBin "xdrush" ''
              #!${pkgs.bash}/bin/bash
              # Create logs directory if it doesn't exist
              mkdir -p $PROJECT_ROOT/data/logs
              mkdir -p $PROJECT_ROOT/data/xdebug_profiles

              if [ "${phpVersion}" = "php74" ] && command -v drush >/dev/null 2>&1; then
                # Use standalone drush with PHP 7.4
                php -d xdebug.mode=debug \
                  -d xdebug.start_with_request=yes \
                  -d xdebug.client_host=localhost \
                  -d xdebug.client_port=9003 \
                  drush "$@"
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
              
              # Check if socket file exists first
              if [ ! -e "$SOCKET" ]; then
                echo "🔴 Process-compose is not running"
                echo "   Expected socket: $SOCKET"
                echo "   Socket file does not exist"
                exit 1
              fi
              
              # Socket file exists, check if it's actually a socket
              if [ ! -S "$SOCKET" ]; then
                echo "🔴 Process-compose socket issue"
                echo "   Socket path: $SOCKET"
                echo "   File exists but is not a socket"
                exit 1
              fi
              
              # Socket exists and is a socket, test if it's responding
              if curl --silent --max-time 3 --unix-socket "$SOCKET" http://localhost/project/state >/dev/null 2>&1; then
                # API is responding - process-compose is ready
                echo "🟢 Process-compose is running and ready"
                echo "   Socket: $SOCKET"
                echo "   Project: ${projectName}"
                
                echo ""
                echo "API Status:"
                API_RESPONSE=$(curl --silent --max-time 2 --unix-socket "$SOCKET" http://localhost/project/state 2>/dev/null)
                if [ -n "$API_RESPONSE" ]; then
                  echo "$API_RESPONSE" | ${pkgs.jq}/bin/jq -r '
                    "   Uptime: " + (.upTime/1000000000 | floor | tostring) + "s" +
                    "\n   Processes: " + (.runningProcessNum | tostring) + "/" + (.processNum | tostring) + " running" +
                    "\n   Version: " + .version' 2>/dev/null || echo "   API parsing failed"
                else
                  echo "   API responded but no data received"
                fi
                exit 0
              else
                # Socket exists but API not responding - process-compose is starting up
                echo "🟡 Process-compose is starting up"
                echo "   Socket: $SOCKET (exists but not ready)"
                echo "   Project: ${projectName}"
                echo "   Status: API not responding yet - still initializing"
                exit 2
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
              echo -e "\033[1;32mphpunit-setup\033[0m           Create phpunit.xml configuration for testing"
              echo -e "\033[1;32mphpunit-module <name>\033[0m    Run PHPUnit tests for a specific module"
              echo -e "\033[1;32mphpunit-custom\033[0m          Run PHPUnit tests for all custom modules and themes"
              echo -e "\033[1;32m?\033[0m                       Show this help message"
              echo ""
              echo -e "Site URL: \033[1;33mhttp://${domain}:${port}\033[0m"
              echo -e "Socket: \033[1;33m''${PC_SOCKET_PATH:-/tmp/process-compose-${projectName}.sock}\033[0m"
            '')
            # Add zip for composer to avoid warnings about corrupted archives
            unzip
            # Add curl for API communication with process-compose
            curl
          ]) ++ localPackages;
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
            
            # Create custom PHP ini file with correct MySQL socket paths  
            mkdir -p "$PWD/data/php-cli"
            # Create custom PHP ini with only MySQL socket overrides
            # We'll still rely on Nix to load extensions via PHP_INI_SCAN_DIR
            cat > "$PWD/data/php-cli/mysql-socket.ini" << INI_EOF
; MySQL socket configuration override for testing
mysqli.default_socket = $DB_SOCKET
pdo_mysql.default_socket = $DB_SOCKET
INI_EOF
            
            # Get the default Nix scan directory and append our custom one
            NIX_SCAN_DIR=$(php --ini | grep "Scan for additional .ini files in:" | cut -d: -f2 | xargs)
            mkdir -p "$PWD/data/php-cli/scan-dir"
            cp "$PWD/data/php-cli/mysql-socket.ini" "$PWD/data/php-cli/scan-dir/99-mysql-socket.ini"
            export PHP_INI_SCAN_DIR="$NIX_SCAN_DIR:$PWD/data/php-cli/scan-dir"
            
            # Create xphpunit wrapper for debugging (similar to xdrush)
            cat > "$PWD/data/php-cli/xphpunit" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# PHPUnit wrapper with Xdebug debugging enabled
# Create logs directory if it doesn't exist  
mkdir -p "$PWD/data/logs"
mkdir -p "$PWD/data/xdebug_profiles"

# Run PHPUnit with Xdebug debugging enabled
php -d xdebug.mode=debug \
  -d xdebug.start_with_request=yes \
  -d xdebug.client_host=localhost \
  -d xdebug.client_port=9003 \
  "$PWD/vendor/bin/phpunit" "$@"
SCRIPT_EOF
            chmod +x "$PWD/data/php-cli/xphpunit"
            
            # Add our wrapper directory to PATH for xphpunit
            export PATH="$PWD/data/php-cli:$PWD/vendor/bin:$PATH"
            
            # PHPUnit environment variables
            export DOMAIN="${domain}"
            export PORT="${port}"
            export DOCROOT="${docroot}"
            export SIMPLETEST_BASE_URL="http://${domain}:${port}"
            export SIMPLETEST_DB="mysql://drupal@localhost/drupal?unix_socket=$PWD/${dbSocket}"
            echo "Entering development environment for ${projectName}"
            echo "Use '?' to see the commands provided in this flake."
          '';
        };
      };
    };
  }
