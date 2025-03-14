## v0.0.1 (2025-03-14)

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
