{
  description = "OpenCode - Fixed 1.1.20 (FHS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      version = "1.1.20";
      
      # 1. Download the raw binary (Impure)
      # We change the name to force a redownload
      src = builtins.fetchurl {
        url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
        name = "opencode-${version}-v1.tar.gz";
      };

      # 2. Extract it WITHOUT patching
      # We just park the binary in a safe place
      unpatched = pkgs.runCommand "opencode-extracted" {} ''
        mkdir -p $out/libexec
        tar -xzf ${src} -C $out/libexec
        # Ensure it's executable
        chmod +x $out/libexec/opencode
      '';

    in
    {
      # 3. Create a wrapper that simulates a standard Linux environment
      packages.${system}.default = pkgs.buildFHSUserEnv {
        name = "opencode";
        
        # OpenCode needs these tools to be available inside the bubble
        targetPkgs = pkgs: with pkgs; [
          zlib
          openssl
          icu
          git      # Essential for an AI coding agent
          ripgrep  # Essential for searching files
          curl
          nodejs   # Often needed for sub-scripts
        ];

        # Run the unpatched binary inside the bubble
        runScript = "${unpatched}/libexec/opencode";
      };
    };
}
