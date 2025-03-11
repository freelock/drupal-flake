{ config, lib, name, pkgs, ... }:
let
  phpVersion = config.phpVersion;
  php = (pkgs.${phpVersion}.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all; [
      curl
      gd
      intl
      pdo_mysql
      soap
      xsl
      xdebug
      zip
    ]);


    extraConfig = ''
      memory_limit = 512M
      display_errors = On
      error_reporting = E_ALL
      xdebug.mode = debug
      xdebug.start_with_request = trigger
      xdebug.client_host = localhost
      xdebug.client_port = 9003
      xdebug.discover_client_host = yes
      xdebug.max_nesting_level = 512
      xdebug.log = /tmp/xdebug.log

      [CLI]
      memory_limit = -1
    '';
  });

in
{
  options = {
    package = lib.mkPackageOption pkgs "init" { };
    projectName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The MySQL data directory";
    };
    php = lib.mkOption {
      type = lib.types.package;
      default = php;
      description = "PHP package to use";
    };
    phpVersion = lib.mkOption {
      type = lib.types.str;
      default = "php83";
      description = "PHP version to use (php74, php80, php81, php82, php83)";
    };
    drupalPackage = lib.mkOption {
      type = lib.types.str;
      default = "drupal/cms";
      description = "Drupal package to install";
    };
  };
  config = {
    outputs.settings = {
      processes.${name} = {
              command = ''
                export PHP_MEMORY_LIMIT=-1
                export PATH="${php}/bin:${config.php.packages.composer}/bin:$PATH"
                if [ ! -f "web/index.php" ]; then
                  echo "Installing Drupal CMS..."
                  composer create-project ${config.drupalPackage} cms
                  mv cms/* ./
                  mv cms/.* ./
                  rmdir cms
                  composer install

                  # Copy settings file without comments and enable local settings include
                  grep -v '^#\|^/\*\|^ \*\|^ \*/\|^$' web/sites/default/default.settings.php | grep -v '^/\*' | grep -v '^ \*' | grep -v '^ \*/' > web/sites/default/settings.php
                  echo 'if (file_exists($$app_root . "/" . $$site_path . "/settings.local.php")) {' >> web/sites/default/settings.php
                  echo '  include $$app_root . "/" . $$site_path . "/settings.local.php";' >> web/sites/default/settings.php
                  echo "}" >> web/sites/default/settings.php

                  mkdir -p web/sites/default/files
                  chmod 777 web/sites/default/settings.php
                  chmod 777 web/sites/default
                fi
                # Create local settings with database configuration
                cat > web/sites/default/settings.nix.php << 'EOL'
                <?php
                $$databases['default']['default'] = [
                  'database' => 'drupal',
                  'username' => "drupal",
                  'password' => "",
                  'host' => 'localhost',
                    'unix_socket' => "$PWD/data/${config.projectName}-db/mysql.sock",
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

                # Skip perms hardening, set config directory
                echo '$$settings["skip_permissions_hardening"] = TRUE;' >> web/sites/default/settings.php
                echo '$$settings["config_sync_directory"] = "../config/sync";' >> web/sites/default/settings.php

                # Include nix settings in main settings.php if not already included
                if ! grep -q "settings.nix.php" web/sites/default/settings.php; then
                  echo 'if (file_exists($$app_root . "/" . $$site_path . "/settings.nix.php")) {' >> web/sites/default/settings.php
                  echo '  include $$app_root . "/" . $$site_path . "/settings.nix.php";' >> web/sites/default/settings.php
                  echo "}" >> web/sites/default/settings.php
                fi


                # Back up settings.php - drush site:install incorrectly adds $databases to settings.php
                cp web/sites/default/settings.php web/sites/default/settings.php.tmp

                drush site:install -y

                # Restore settings.php
                mv web/sites/default/settings.php.tmp web/sites/default/settings.php
              '';
      };
    };
  };
}
