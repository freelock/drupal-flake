{ config, lib, name, pkgs, ... }:
let
  phpVersion = config.phpVersion;
  php = (pkgs.${phpVersion}.buildEnv {
    extensions = { enabled, all }:
      enabled ++ (with all; [ curl gd intl pdo_mysql soap xsl xdebug zip ]);

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

  # Create helper script packages
  nix-settings =
    pkgs.writeScriptBin "nix-settings" (builtins.readFile ./bin/nix-settings);
  drupal-download = pkgs.writeScriptBin "drupal-download"
    (builtins.readFile ./bin/drupal-download);
  drupal-recipe =
    pkgs.writeScriptBin "drupal-recipe" (builtins.readFile ./bin/drupal-recipe);
  drupal-install = pkgs.writeScriptBin "drupal-install"
    (builtins.readFile ./bin/drupal-install);

in {
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
      description =
        "Custom project name to use (if provided, will create .env file)";
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
      export PATH="${php}/bin:${config.php.packages.composer}/bin:${drupal-download}/bin:${drupal-recipe}/bin:${drupal-install}/bin:${nix-settings}/bin:$(pwd)/vendor/bin:$(pwd)/bin:$PATH"

      # Create .env file if custom project name is provided
      if [ -n "${config.customProjectName}" ] && [ ! -f ".env" ] && [ -f ".env.example" ]; then
        echo "Creating .env file with custom project name: ${config.customProjectName}"
        cp .env.example .env
        sed -i 's/^# PROJECT_NAME=.*/PROJECT_NAME=${config.customProjectName}/' .env
      fi

      # Create data directory early to avoid race conditions
      if [ ! -d "data" ]; then
        echo "Creating data directory..."
        mkdir -p data
      fi

      if [ ! -f "web/index.php" ]; then
        # Use environment variables if set, otherwise use config defaults
        DRUPAL_PKG="''${DEMO_DRUPAL_PACKAGE:-${config.drupalPackage}}"
        COMPOSER_OPTS="''${DEMO_COMPOSER_OPTIONS:-${config.composerOptions}}"
        RECIPE="''${DEMO_RECIPE:-${config.recipe}}"
        
        echo "========================================="
        echo "Drupal Installation Process"
        echo "Package: $DRUPAL_PKG"
        if [ -n "$RECIPE" ]; then
          echo "Recipe: $RECIPE"
        fi
        echo "========================================="
        
        # Step 1: Download Drupal using drupal-download helper
        echo ""
        echo "Step 1: Downloading Drupal package..."
        drupal-download "$DRUPAL_PKG" "" "$COMPOSER_OPTS" 2>&1 | tee -a data/install.log

        if [ ''${PIPESTATUS[0]} -ne 0 ]; then
          echo "❌ Download step failed! Check data/install.log"
          exit 1
        fi
        
        # Step 2: Install site template recipe if specified
        if [ -n "$RECIPE" ] && echo "$RECIPE" | grep -qE "^[a-z]+/[a-z_]+$"; then
          # Recipe looks like a composer package (drupal/haven format)
          echo ""
          echo "Step 2: Installing site template recipe..."
          drupal-recipe "$RECIPE" 2>&1 | tee -a data/install.log

          if [ ''${PIPESTATUS[0]} -ne 0 ]; then
            echo "⚠️  Recipe installation had issues, will try to continue..."
          fi
        fi
        
        # Step 3: Run the actual Drupal installation
        echo ""
        echo "Step 3: Installing Drupal..."
        drupal-install "$RECIPE" "-y" 2>&1 | tee -a data/install.log

        if [ ''${PIPESTATUS[0]} -ne 0 ]; then
          echo "❌ Installation failed! Check data/install.log"
          # Try to identify the issue
          if grep -q "Module.*not found" data/install.log 2>/dev/null; then
            echo ""
            echo "Missing modules detected. Trying auto-fix..."
            # Extract and install missing modules
            MISSING=$(grep -oE "Module ['\"]?[a-z_]+['\"]? not found" data/install.log | \
              sed -E "s/.*['\"]?([a-z_]+)['\"]?.*/\1/" | sort -u)
            for module in $MISSING; do
              echo "Installing missing module: $module"
              composer require drupal/$module --with-all-dependencies 2>&1 | tee -a data/install.log || true
            done
            # Retry installation
            echo "Retrying installation with new modules..."
            drupal-install "$RECIPE" "-y" 2>&1 | tee -a data/install.log
          fi
          exit 1
        fi
        
        echo ""
        echo "✅ Drupal installation complete!"
      else
        echo "Drupal CMS already installed"
      fi
    '';

    outputs.settings = {
      processes.${name} = { command = "${config.package}/bin/init"; };
    };
  };
}
