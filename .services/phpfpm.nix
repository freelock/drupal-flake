{ config, lib, name, pkgs, ... }:
let
  php = pkgs.php83.buildEnv {
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
      xdebug.start_with_request = yes
      xdebug.client_host = localhost
      xdebug.client_port = 9003
      xdebug.discover_client_host = yes
      xdebug.log = /tmp/xdebug.log
    '';
  };

  phpEnv = pkgs.buildEnv {
    name = "phpEnv";
    paths = [ php php.packages.composer ];
  };

  phpfpmConfig = pkgs.writeText "php-fpm.conf" ''
    [global]
    pid = php-fpm-${name}.pid
    error_log = php-fpm.log
    daemonize = no

    [www]
    listen = /tmp/${name}.sock
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
  };

  config = {
    outputs = {
      settings.processes."${name}" = {
        command = ''
          mkdir -p ${config.dataDir}
          ${phpEnv}/bin/php-fpm --nodaemonize -p ${config.dataDir} --fpm-config ${phpfpmConfig}
        '';
      };
    };
  };
}
