{
  description = "Declarative Android app provisioning via adb, gplaydl, fdroidcl, and GitHub releases";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          gplaydl = pkgs.python3Packages.callPackage ./pkgs/gplaydl { };
          declaroid = pkgs.callPackage ./pkgs/declaroid { inherit gplaydl; };
        in
        {
          inherit gplaydl declaroid;
          default = declaroid;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.declaroid}/bin/declaroid";
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
