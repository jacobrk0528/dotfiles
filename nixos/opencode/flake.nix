{
  description = "OpenCode Flake - Custom Build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      
      # 1. Define the version you saw in the installer
      version = "1.1.20"; 
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "opencode";
        inherit version;

        # 2. Fetch the generic Linux binary (The same one the curl script downloads)
        src = pkgs.fetchurl {
          url = "https://github.com/opencode-ai/opencode/releases/download/v${version}/opencode-linux-x86_64.tar.gz";
          # Nix will complain about the hash first. Copy the hash it gives you and paste it here.
          sha256 = "sha256-0000000000000000000000000000000000000000000000000000"; 
        };

        # 3. The Magic Sauce: Auto-patching
        # This hook automatically finds "bad" dynamic links (like /lib64/ld-linux...) 
        # and replaces them with the correct paths in /nix/store.
        nativeBuildInputs = [ 
          pkgs.autoPatchelfHook 
        ];

        # 4. Runtime Dependencies
        # These are the libraries the binary likely needs. 
        # Since it's a Go/BubbleTea app (based on standard AI agents), it usually needs these:
        buildInputs = with pkgs; [
          zlib
          stdenv.cc.cc.lib # libstdc++
          openssl
        ];

        # 5. Extract and Install
        # The tarball usually contains just the binary. We copy it to $out/bin.
        sourceRoot = ".";
        installPhase = ''
          install -m755 -D opencode $out/bin/opencode
        '';
      };
    };
}
