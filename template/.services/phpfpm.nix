{ config, lib, name, pkgs, ... }:
let
  # Use the custom pkgs if provided, otherwise use the default
  finalPkgs = if config ? pkgs then config.pkgs else pkgs;
  phpVersion = config.phpVersion;
  php = (finalPkgs.${phpVersion}.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all; [
      curl
      gd
      imagick
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
      # Disable socket override until can find a better way to do this
      # mysqli.default_socket = ${config.dbSocket}
    '';
  });

  # Determine paths based on PHP version - several packages aren't available in php74
  phpPaths =
    if phpVersion == "php74" then [
      php
      php.packages.composer
      finalPkgs.mysql-client
    ] ++ lib.optional (finalPkgs ? drush) finalPkgs.drush
    else [
      php
      php.packages.composer
      php.packages.phpstan
      php.packages.php-codesniffer
      finalPkgs.phpunit
      finalPkgs.mysql-client
    ];

  phpEnv = finalPkgs.buildEnv {
    name = "phpEnv";
    paths = phpPaths;
  };

  phpfpmConfig = pkgs.writeText "php-fpm.conf" ''
    [global]
    pid = php-fpm-${name}.pid
    error_log = php-fpm.log
    daemonize = no

    [www]
    listen = /tmp/${name}.sock
    clear_env = no
    pm = dynamic
    pm.max_children = 5
    pm.start_servers = 2
    pm.min_spare_servers = 1
    pm.max_spare_servers = 3
  '';
in
{
  options = {
    package = lib.mkOption {
      type = lib.types.package;
      default = phpEnv;
      description = "PHP package to use";
    };
    phpVersion = lib.mkOption {
      type = lib.types.str;
      default = "php83";
      description = "PHP version to use (php74, php80, php81, php82, php83, php84)";
    };
    pkgs = lib.mkOption {
      type = lib.types.attrs;
      default = pkgs;
      description = "The package set to use for PHP";
    };
    dbSocket = lib.mkOption {
      type = lib.types.str;
      default = "data/db/mysql.sock";
      description = "The MySQL socket path";
    };
  };

  config = {
    outputs = {
      settings = {
        processes."${name}" = {
          command = ''
            mkdir -p ${config.dataDir}
            ${phpEnv}/bin/php-fpm --nodaemonize -p ${config.dataDir} --fpm-config ${phpfpmConfig}
          '';
	        # To support project browser/auto updates, need path to composer and rsync.
          environment = [
            "PATH=${phpEnv}/bin:${pkgs.coreutils}/bin:${pkgs.rsync}/bin:${pkgs.bash}/bin"
          ];
        };
      };
    };
  };
}
