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

      # `nix flake check` builds these: shellcheck + `bash -n` against the
      # main script and every test file (a real derivation, not just
      # flake-schema validation), an actionlint pass over the CI workflow,
      # plus the bats unit suite -- the same commands CI's lint/unit jobs
      # run, just also reachable with a single plain `nix flake check`.
      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          shellcheck =
            pkgs.runCommand "declaroid-shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                bash -n ${./declaroid}
                shellcheck ${./declaroid}
                shellcheck ${./tests/unit}/*.bats ${./tests/unit/helpers}/*.bash
                shellcheck ${./tests/e2e}/*.bats ${./tests/e2e/helpers}/*.bash
                touch "$out"
              '';

          actionlint = pkgs.runCommand "declaroid-actionlint" { nativeBuildInputs = [ pkgs.actionlint ]; } ''
            actionlint ${./.github/workflows/ci.yml}
            touch "$out"
          '';

          # Deliberately run with no LANG/LC_ALL override -- the Nix build
          # sandbox's default locale is effectively `C`, which is exactly
          # what caught a real, previously-latent bug (see ROW_SEP's
          # comment in declaroid): keeping this un-pinned means any future
          # locale-dependent regression fails `nix flake check` again
          # instead of silently only showing up on a stray non-UTF-8
          # deployment target.
          bats-unit =
            pkgs.runCommand "declaroid-bats-unit"
              {
                nativeBuildInputs = [
                  pkgs.bats
                  pkgs.yq-go
                  pkgs.jq
                ];
              }
              ''
                export DECLAROID_SCRIPT=${./declaroid}
                bats ${./tests/unit}
                touch "$out"
              '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              # Runtime deps (mirrors pkgs/declaroid/default.nix's wrapProgram
              # PATH, minus the ones already ambient in a dev shell)
              pkgs.android-tools
              pkgs.yq-go
              pkgs.jq
              pkgs.aapt
              pkgs.fdroidcl
              pkgs.fzf

              # Lint/format/test tooling
              pkgs.shellcheck
              pkgs.nixfmt
              pkgs.statix
              pkgs.bats
              pkgs.actionlint
            ];
          };
        }
      );
    };
}
