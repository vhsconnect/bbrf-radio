# waybar integration for the bbrf always-on radio: exposes a
# `custom/radio` module config as services.bbrf.waybar.settings, ready to
# merge into any waybar bar config (home-manager or otherwise).
# System-independent, like nix/module.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.bbrf;

  # Built by nix/radio-waybar.nix (also exposed as the standalone flake
  # package `radio-waybar`) with this host's option values.
  radioWaybar = pkgs.callPackage ./radio-waybar.nix {
    socket = cfg.alwaysOnRadio.socket;
    defaultStation = cfg.alwaysOnRadio.defaultStation;
  };
in
{
  options.services.bbrf.waybar = {

    enable = mkEnableOption ''
      a `custom/radio` waybar module showing mute state, station and
      current title of the always-on radio. The module config is exposed
      as `settings` for your waybar config to merge; `on-click` uses the
      `radio` CLI. Linux only.
    '';

    format = mkOption {
      type = types.str;
      default = "  {}";
      description = ''
        waybar `format` of the radio module.
      '';
    };

    interval = mkOption {
      type = types.int;
      default = 2;
      description = ''
        Seconds between status updates.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      readOnly = true;
      description = ''
        waybar `custom/radio` module config, ready to merge into a bar
        config.
      '';
    };

  };

  config = mkIf cfg.waybar.enable {
    assertions = [
      {
        assertion = cfg.alwaysOnRadio.enable;
        message = "services.bbrf.waybar requires services.bbrf.alwaysOnRadio";
      }
    ];

    services.bbrf.waybar.settings = {
      exec = "${radioWaybar}/bin/radio-waybar";
      exec-if = ''test -S "${cfg.alwaysOnRadio.socket}"'';
      return-type = "json";
      restart-interval = 4;
      interval = cfg.waybar.interval;
      format = cfg.waybar.format;
      tooltip = true;
      on-click = "radio toggle";
    };
  };
}
