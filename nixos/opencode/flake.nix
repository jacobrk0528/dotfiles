{
  description = "OpenCode - Fixed 1.1.65 (FHS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      version = "1.1.65";
      
      # 1. Download the raw binary
      src = builtins.fetchurl {
        url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
        name = "opencode-${version}-v1.tar.gz";
      };

      # 2. Extract it WITHOUT patching
      unpatched = pkgs.runCommand "opencode-extracted" {} ''
        mkdir -p $out/libexec
        tar -xzf ${src} -C $out/libexec
        chmod +x $out/libexec/opencode
      '';

    in
    {
      # 3. Create the FHS environment
      # CHANGED: buildFHSUserEnv -> buildFHSEnv
      packages.${system}.default = pkgs.buildFHSEnv {
        name = "opencode";
        
        targetPkgs = pkgs: with pkgs; [
          zlib
          openssl
          icu
          git
          ripgrep
          curl
          nodejs
          stdenv.cc.cc.lib # Added C++ libs which are often needed
        ];

        runScript = "${unpatched}/libexec/opencode";
      };
    };
}
