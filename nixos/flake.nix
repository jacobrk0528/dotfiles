{
  description = "OpenCode - Always Latest (Impure)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      
      # FIX: We added '.tar.gz' to the name so 'unpackPhase' knows what to do.
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

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];

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
