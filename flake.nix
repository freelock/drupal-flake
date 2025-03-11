{
  description = "Template for Drupal development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs = inputs @ { self, nixpkgs, flake-parts, systems, process-compose-flake, services-flake, ... }:
  let
    templateFlake = import ./template/flake.nix;
    templateOutputs = templateFlake.outputs inputs;

  in
  {
    templates.default = {
      path = ./template;
      description = "Development environment for Drupal with Nix";
      welcomeText = ''
        # Drupal Development Environment

        Your new Drupal environment has been created!


        To get started:

        1. Edit .env to configure your project and add to git

        2. Run `direnv allow`

        3. Run `nix run` to start the environment

        4. Add .direnv, data and other environment-related dirs/files to .gitignore

        ```
        echo -e ".direnv\n/data\n/logs" >> .gitignore
        ```

      '';
    };

    # Re-export the template's outputs to maintain direct usability
    inherit (templateOutputs)
      packages
      apps
      devShells;
  };
}
