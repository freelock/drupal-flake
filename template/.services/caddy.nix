{ config, lib, name, pkgs, ... }:
let


  caddyfile = pkgs.writeText "Caddyfile" ''
    {

      local_certs
      http_port 8080
      https_port 8443
    }
    ${config.settings.domain} = {
      root * /home/john/git/service-flake/web
      encode gzip
      log
      php_fastcgi unix//tmp/php-php.sock
      file_server

      @hiddenFilesRegexp path_regexp (^|/)\.
      error @hiddenFilesRegexp 403

      @hiddenPhpFilesRegexp path_regexp \..*/.*\.php$
      error @hiddenPhpFilesRegexp 403

      @vendorPhpFiles path /vendor/.*\.php$
      error @vendorPhpFiles 404

      @sitesFilesPhpFilesRegexp path_regexp ^/sites/[^/]+/files/.*\.php$
      error @sitesFilesPhpFilesRegexp 404

      @privateDirRegexp path_regexp ^/sites/.*/private/
      error @privateDirRegexp 403

      @protectedFilesRegexp {
        path_regexp \.(engine|inc|install|make|module|profile|po|sh|.*sql|theme|twig|tpl(\.php)?|xtmpl|yml)(~|\.sw[op]|\.bak|\.orig|\.save)?$|^(Entries.*|Repository|Root|Tag|Template|composer\.(json|lock)|web\.config)$|^#.*#$|\.php(~|\.sw[op]|\.bak|\.orig|\.save)$
      }
      error @protectedFilesRegexp 404

      @staticFiles path_regexp \.(avif|css|eot|gif|gz|ico|jpg|jpeg|js|otf|pdf|png|svg|ttf|webp|woff|woff2)
      header @staticFiles Cache-Control "max-age=31536000,public,immutable"

      @privateFiles path_regexp ^(/[a-z\-]+)?/system/files/
      handle @privateFiles {
        try_files {path} /index.php?{query}
      }
    }
  '';

  # Helper script to add localhost entry
  setupHostsScript = pkgs.writeScript "setup-hosts.sh" ''
    #!${pkgs.bash}/bin/bash
    echo "This script requires sudo access to add an entry to your hosts file."
    echo "You may be prompted for your password."
    echo "Adding entry for ${config.settings.domain} to /etc/hosts"
    if ! grep -q ${config.settings.domain} /etc/hosts; then
      echo "127.0.0.1 ${config.settings.domain}" | sudo tee -a /etc/hosts
      echo "Entry added successfully"
    else
      echo "Entry already exists"
    fi
  '';
in
{
  options = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.caddy;
      description = "Caddy package to use";
    };
    settings = {
      domain = lib.mkOption {
        type = lib.types.str;
        default = "${name}.local";
        description = "Domain to serve";
      };
    };
  };

  config = {
    outputs.settings = {
      processes."${name}" = {
        command = ''
          ${setupHostsScript}/bin/setup-hosts.sh
          ${pkgs.caddy}/bin/caddy run --config ${caddyfile} --adapter caddyfile
        '';
        working_dir = ".";

      };

    };
  };
}
