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
      memory_limit = ${config.maxRam}
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

  # Create nix-settings package separately
  nix-settings = pkgs.writeScriptBin "nix-settings" (builtins.readFile ./bin/nix-settings);

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
    dbSocket = lib.mkOption {
      type = lib.types.str;
      default = "data/db/mysql.sock";
      description = "The MySQL socket path";
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
    composerOptions = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Additional options to pass to composer create-project";
    };
    recipe = lib.mkOption {
      type = lib.types.str;
      default = "";
      description =
        "Drupal recipe to install (e.g., recipes/byte, standard, minimal). If empty, uses default install";
    };
    customProjectName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Custom project name to use (if provided, will create .env file)";
    };
    maxRam = lib.mkOption {
      type = lib.types.str;
      default = "512M";
      description = "PHP memory limit";
    };
  };
  config = {
    package = pkgs.writeScriptBin "init" ''
      #!${pkgs.bash}/bin/bash
      export PHP_MEMORY_LIMIT=-1
      # Support both vendor/bin (standard) and bin/ (kickstart-style) for binaries
      export PATH="${php}/bin:${config.php.packages.composer}/bin:$(pwd)/vendor/bin:$(pwd)/bin:$PATH"

      # Create .env file if custom project name is provided
      if [ -n "${config.customProjectName}" ] && [ ! -f ".env" ] && [ -f ".env.example" ]; then
        echo "Creating .env file with custom project name: ${config.customProjectName}"
        cp .env.example .env
        sed -i 's/^# PROJECT_NAME=.*/PROJECT_NAME=${config.customProjectName}/' .env
      fi
      
      if [ ! -f "web/index.php" ]; then
        # Use environment variables if set, otherwise use config defaults
        DRUPAL_PKG="''${DEMO_DRUPAL_PACKAGE:-${config.drupalPackage}}"
        COMPOSER_OPTS="''${DEMO_COMPOSER_OPTIONS:-${config.composerOptions}}"
        
        echo "Installing Drupal package: $DRUPAL_PKG..."
        
        # Determine the project name from the package (last part after /)
        PROJECT_DIR=$(echo "$DRUPAL_PKG" | sed 's/.*\///' | sed 's/-project$//')
        
        # Run composer create-project - it will create a directory based on the package name
        composer create-project $DRUPAL_PKG $COMPOSER_OPTS
        
        # Find the directory that was just created (most recent directory)
        # For drupal/cms -> creates "cms"
        # For centarro/commerce-kickstart-project -> creates "kickstart"
        if [ -d "$PROJECT_DIR" ]; then
          INSTALL_DIR="$PROJECT_DIR"
        elif [ -d "cms" ]; then
          INSTALL_DIR="cms"
        elif [ -d "kickstart" ]; then
          INSTALL_DIR="kickstart"
        else
          # Find the most recently created directory
          INSTALL_DIR=$(ls -td */ 2>/dev/null | head -1 | sed 's:/$::')
          echo "Detected install directory: $INSTALL_DIR"
        fi
        
        if [ -z "$INSTALL_DIR" ] || [ ! -d "$INSTALL_DIR" ]; then
          echo "Error: Could not find installation directory"
          exit 1
        fi
        
        echo "Moving files from $INSTALL_DIR directory..."
        
        # Move files from install directory, handling conflicts carefully
        for item in "$INSTALL_DIR"/*; do
          [ -e "$item" ] || continue  # Skip if glob didn't match anything
          basename_item=$(basename "$item")
          if [ -e "$basename_item" ]; then
            echo "Warning: $basename_item already exists, merging contents..."
            if [ -d "$item" ] && [ -d "$basename_item" ]; then
              # Merge directories
              cp -r "$item"/* "$basename_item"/ 2>/dev/null || true
              cp -r "$item"/.[^.]* "$basename_item"/ 2>/dev/null || true
            else
              # Replace files
              rm -rf "$basename_item"
              mv "$item" ./
            fi
          else
            mv "$item" ./
          fi
        done
        
        # Move hidden files (excluding . and ..)
        for item in "$INSTALL_DIR"/.[^.]*; do
          [ -e "$item" ] || continue  # Skip if glob didn't match anything
          basename_item=$(basename "$item")
          if [ -e "$basename_item" ]; then
            echo "Warning: hidden file $basename_item already exists, replacing..."
            rm -rf "$basename_item"
          fi
          mv "$item" ./
        done
        
        # Remove install directory if empty, otherwise warn
        if rmdir "$INSTALL_DIR" 2>/dev/null; then
          echo "Cleaned up $INSTALL_DIR directory"
        else
          echo "Warning: $INSTALL_DIR directory not empty, contents:"
          ls -la "$INSTALL_DIR"/ || true
        fi
        
        # Run composer install to ensure dependencies are up to date
        composer install
        
        # Install drush if not present (vanilla core doesn't include it)
        if [ ! -f "vendor/bin/drush" ] && [ ! -f "bin/drush" ]; then
          echo "Drush not found, installing..."
          composer require drush/drush --with-all-dependencies
        fi

        # Copy settings file without comments and enable local settings include
        grep -v '^#\|^/\*\|^ \*\|^ \*/\|^$' web/sites/default/default.settings.php | grep -v '^/\*' | grep -v '^ \*' | grep -v '^ \*/' > web/sites/default/settings.php
        echo 'if (file_exists($app_root . "/" . $site_path . "/settings.local.php")) {' >> web/sites/default/settings.php
        echo '  include $app_root . "/" . $site_path . "/settings.local.php";' >> web/sites/default/settings.php
        echo "}" >> web/sites/default/settings.php

        # Skip perms hardening, set config directory
        echo '$settings["skip_permissions_hardening"] = TRUE;' >> web/sites/default/settings.php
        echo '$settings["config_sync_directory"] = "../config/sync";' >> web/sites/default/settings.php

        # Run nix-settings to configure database and development settings
        ${nix-settings}/bin/nix-settings ${config.projectName} web ${config.dbSocket}

        chmod 777 web/sites/default/settings.php
        chmod 777 web/sites/default

        # Back up settings.php - drush site:install adds $databases to end of settings.php
        # which conflicts with our nix-settings configuration
        cp web/sites/default/settings.php web/sites/default/settings.php.tmp

        # Use recipe if specified, otherwise use default install
        RECIPE="''${DEMO_RECIPE:-${config.recipe}}"
        if [ -n "$RECIPE" ]; then
          echo "Installing Drupal with recipe: $RECIPE"
          drush site:install "$RECIPE" -y
        else
          echo "Installing Drupal..."
          drush site:install standard -y
        fi

        # Restore settings.php to remove the database block drush added
        # Our nix-settings.php handles database configuration separately
        mv web/sites/default/settings.php.tmp web/sites/default/settings.php
        
        # Clear caches after installation to ensure site loads properly
        echo "Clearing caches..."
        drush cache:rebuild || true
      else
        echo "Drupal CMS already installed"
      fi
    '';

    outputs.settings = {
      processes.${name} = {
        command = "${config.package}/bin/init";
      };
    };
  };
}
