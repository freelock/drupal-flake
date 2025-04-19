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
    package = pkgs.writeScriptBin "config" ''
      #!${pkgs.bash}/bin/bash
      export PHP_MEMORY_LIMIT=-1
      export PATH="${php}/bin:${config.php.packages.composer}/bin:$(pwd)/vendor/bin:$PATH"
      # if [ ! -f "web/index.php" ]; then
        echo "Installing Drupal CMS..."

        composer install

        chmod 777 web/sites/default/settings.php
        chmod 777 web/sites/default

        # Back up settings.php - drush site:install incorrectly adds $databases to settings.php
        # cp web/sites/default/settings.php web/sites/default/settings.php.tmp

        drush site:install --existing-config -y

        # Restore settings.php
        # mv web/sites/default/settings.php.tmp web/sites/default/settings.php
      #else
      #  echo "Drupal already installed"
      # fi
    '';

    outputs.settings = {
      processes.${name} = {
        command = "${config.package}/bin/config";
      };
    };
  };
}
