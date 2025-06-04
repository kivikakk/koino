{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;
      in
      rec {
        formatter.default = pkgs.nixfmt-rfc-style;

        packages.default = pkgs.stdenv.mkDerivation {
          name = "koino-build";
          src = ./.;

          nativeBuildInputs = [
            pkgs.zig
          ];

          buildPhase = ''
            export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig"
            zig build
            mkdir -p $out/bin
            mv zig-out/bin/koino $out/bin/koino
          '';

          dontInstall = true;
        };
      }
    );
}
