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

      perSystem = { self', pkgs, config, lib, ...}: {
        process-compose."default" = { config, ...}:
          let
            projectName = "drupal-demo";
            domain = "${projectName}.local";
            port = "8088";
            inherit (inputs.services-flake.lib) multiService;
          in
          {
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
              };
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
                sleep 5
                xdg-open http://${domain}:${port}
              '';
              depends_on."${projectName}-nginx".condition = "process_healthy";
            };
          };
        devShells.default = pkgs.mkShell {
          inputsFrom = [
            config.process-compose."default".services.outputs.devShell

          ];
        };
      };
    };
  }
