{
  description = "OpenCode - Always Latest (Impure)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Fetches the file at run time.
      # Note the name ends in .tar.gz so Nix knows how to unpack it.
      binaryTarball = builtins.fetchurl {
        url = "https://github.com/opencode-ai/opencode/releases/latest/download/opencode-linux-x86_64.tar.gz";
        name = "opencode-latest.tar.gz"; 
      };
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "opencode";
        version = "latest";

        src = binaryTarball;

        # 1. Patch the binary to use Nix loader
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];

        # 2. Link necessary libraries
        buildInputs = with pkgs; [
          zlib
          stdenv.cc.cc.lib
          openssl
        ];

        sourceRoot = ".";
        installPhase = ''
          install -m755 -D opencode $out/bin/opencode
        '';
      };
    };
}
