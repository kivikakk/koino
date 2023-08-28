{
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
    in rec {
      packages.default = pkgs.stdenv.mkDerivation {
        name = "koino-build";

        src = ./.;

        nativeBuildInputs = [pkgs.zig pkgs.pcre pkgs.python311];

        buildPhase = ''
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig"
          zig build test
          touch $out
        '';

        dontInstall = true;
      };

      packages.specs = packages.default.overrideAttrs {
        buildPhase = ''
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig"
          make spec
          touch $out
        '';
      };

      formatter = pkgs.alejandra;
    });
}
