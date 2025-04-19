{ config, lib, name, pkgs, ... }:

{
  options = {
    package = lib.mkPackageOption pkgs "nix-settings" { };
    projectName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The project name for MySQL socket path";
    };
    dbSocket = lib.mkOption {
      type = lib.types.str;
      default = "data/db/mysql.sock";
      description = "The MySQL socket path";
    };
    domain = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The domain name";
    };
    port = lib.mkOption {
      type = lib.types.str;
      default = "80";
      description = "The port number";
    };
    docroot = lib.mkOption {
      type = lib.types.str;
      default = "web";
      description = "The document root";
    };
    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = "../";
      description = "The relative path from docroot to project root";
    };
  };

  config = {
    package = pkgs.writeScriptBin "nix-settings" (builtins.readFile ./bin/nix-settings);
    outputs.settings = {
      processes.${name} = {
        command = ''
          ${pkgs.writeScript "nix-settings" (builtins.readFile ./bin/nix-settings)} ${config.projectName} ${config.docroot} ${config.dbSocket} ${config.projectRoot}
        '';
      };
    };
  };
}
