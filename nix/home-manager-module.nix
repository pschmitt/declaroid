# Home Manager module for declaroid, exposed as `homeManagerModules.default`
# by the flake. Curried on `self` so it can reach `self.packages.<system>`
# for the actual package -- everything below this line is the real module
# (config/lib/pkgs come from whichever Home Manager evaluation imports it).
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.declaroid;
  system = pkgs.stdenv.hostPlatform.system;
in
{
  options.programs.declaroid = {
    enable = lib.mkEnableOption "declaroid, declarative Android app/module provisioning over adb";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.default;
      description = "The declaroid package to install.";
    };

    configPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression ''"''${config.home.homeDirectory}/dotfiles/android/all.yaml"'';
      description = ''
        Out-of-store path declaroid should resolve as its default config
        (`''${XDG_CONFIG_HOME:-$HOME/.config}/declaroid/apps.yaml`) when
        invoked with no `-c`/`--config`. Symlinked directly with
        `mkOutOfStoreSymlink` rather than copied into the Nix store: a
        *meta-config*'s `configs:` fan-out list (see declaroid's own
        README) is resolved relative to the config file's own on-disk
        directory, which only exists in a real checkout -- a store copy
        would have no sibling device files to find.

        This is also why `$DECLAROID_CONFIG` alone isn't a reliable way to
        point at the same file: any shell whose environment was
        established before that variable existed (a long-lived tmux pane,
        a stale SSH session predating the change) never re-sources it and
        silently falls back to whatever `apps.yaml` happens to already be
        at that default path -- which, under `apply --enforce`, can mean
        offering to uninstall every app the *intended* config actually
        declares. Managing the default path itself via this option instead
        makes it correct in every context (cron, a systemd unit, a brand
        new login) with no dependency on session-variable sourcing at all.

        Leave as `null` to not manage
        `''${XDG_CONFIG_HOME:-$HOME/.config}/declaroid/apps.yaml` at all.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."declaroid/apps.yaml" = lib.mkIf (cfg.configPath != null) {
      source = config.lib.file.mkOutOfStoreSymlink cfg.configPath;
    };
  };
}
