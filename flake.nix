{
  description = "Template for Drupal development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-php74.url = "github:NixOS/nixpkgs/6e3a86f2f73a466656a401302d3ece26fba401d9";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake/8bc6dff1c0d82842b28e3906ac4645a3c3a49dbe";
  };

  outputs = inputs @ { self, nixpkgs, nixpkgs-php74, flake-parts, systems, process-compose-flake, services-flake, ... }:
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

        ## Quick Start:

        1. Edit .env to configure your project and add to git.
        2. Run `direnv allow` (optional).
        3. Run `nix develop` to get a devShell.
        4. Run `?` to see all available commands.
        5. Use `start-detached` to start in background, or `start-demo` for a quick demo.
        6. Add .direnv, data and other environment-related dirs/files to .gitignore.

        ```
        echo -e ".direnv\n/data" >> .gitignore
        ```

        ## Key Commands:
        - `start-detached` - Start development environment in background
        - `pc-status` - Check if services are running
        - `pc-attach` - Connect to running services TUI
        - `pc-stop` - Stop services for this project
        - `setup-starship-prompt` - Add status indicator to your shell prompt

        ## Development Workflow:
        1. `start-detached` - Start services in background
        2. `pc-status` - Verify everything is running
        3. Code away! The starship prompt shows when services are active.
        4. `pc-stop` - Stop when done

        Run `?` in the devShell for complete command reference.
      '';
    };

    # Re-export the template's outputs to maintain direct usability
    inherit (templateOutputs)
      packages
      apps
      devShells;
  };
}
