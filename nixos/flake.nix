{
  description = "Jacob's NixOS Flake Configuration";

  inputs = {
    # Official NixOS package source
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # The OpenCode flake you wanted
    opencode-flake.url = "path:./opencode";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.jkrebs-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      
      # This line is special: it passes 'inputs' to all your modules
      # so you can use them in configuration.nix
      specialArgs = { inherit inputs; };
      
      modules = [
        ./configuration.nix
      ];
    };
  };
}
