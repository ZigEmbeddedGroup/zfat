{
  description = "TurtleFont, a small vector graphics font file.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      # Other overlays
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
      })
    ];

    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system;};
      in let
        zig = pkgs.zigpkgs."0.13.0";
      in rec {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "turtlefont";
          src = ./.;
          nativeBuildInputs = [zig];

          configurePhase = "";

          buildPhase = ''
            zig build
          '';

          installPhase = ''
            mv zig-out $out
          '';
        };
      }
    );
}
