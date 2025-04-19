
### Feat

- **scripts**: helper scripts for development of this flake
- **drush**: set the options uri for drush
- **nix-settings**: configure database settings on existing sites
- **phpPackages**: add phpstan, php-codesniffer, imagick
- **template**: add a default template to install this flake locally
- **drupalPackage**: select a drupal package to install other than drupal/cms
- **.env**: use environment variables to set default values
- **nix-run**: make nix run work without being in the devShell
- **demo**: download and install Drupal CMS as a nix run target

### Fix

- **nginx**: support large headers for drupal dev, extend timeout for debug
- **shellHook**: Fix quoting on shellHook
- **nginx**: fix always binding to port 8080
- **mysql**: make project portable - look up current path

## 0.0.1 (2025-04-06)

### Feat

- **start-config**: Add an install from config run target, and set more consistent script names
- **settings**: Make nix include more compatible with non-flake environments
- **xdrush**: New command to trigger an xdebug session with drush
- **php-fpm**: Add phpEnv paths to environment for php-fpm
- **refresh-flake**: Add refresh-flake to devshell
- **scripts**: helper scripts for development of this flake
- **drush**: set the options uri for drush
- **nix-settings**: configure database settings on existing sites
- **phpPackages**: add phpstan, php-codesniffer, imagick
- **template**: add a default template to install this flake locally
- **drupalPackage**: select a drupal package to install other than drupal/cms
- **.env**: use environment variables to set default values
- **nix-run**: make nix run work without being in the devShell
- **demo**: download and install Drupal CMS as a nix run target

### Fix

- **mysql**: Set recommended transaction_isolation setting
- **phpfpm**: Set pool to pass in env vars so project browser can get the path
- **phpfpm**: Send environment option instead of incorrect env option
- **refresh-flake**: Set PROJECT_ROOT to project directory, not store directory
- **site:install**: Explicitly add vendor/bin to path
- **site:install**: use full path to drush to fix remote installations
- **nginx**: support large headers for drupal dev, extend timeout for debug
- **shellHook**: Fix quoting on shellHook
- **nginx**: fix always binding to port 8080
- **mysql**: make project portable - look up current path
