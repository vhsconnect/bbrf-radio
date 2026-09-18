# Options for services.bbrf, shared by the NixOS module (nix/module.nix)
# and the nix-darwin module (nix/darwin-module.nix).
{
  lib,
  pkgs,
  ...
}:

with lib;

{
  options.services.bbrf = {

    enable = mkEnableOption ''
      Browser, play and favorite internet radios in your browser.
    '';

    port = mkOption {
      type = types.int;
      default = 3335;
      description = ''
        The port the service should bind to.
      '';
    };
    faderValue = mkOption {
      type = types.int;
      default = 25;
      description = ''
        the fader value is the how long it takes in miliseconds to fade 1/100th bit of volume in each direction. Higher values fade the radios more slowly. Recommended values are between 15 and 50 ms. 

      '';
    };

    itemsPerPage = mkOption {
      type = types.int;
      default = 5000;
      description = ''
        Items per page when returning results from radio list queries. Bigger limits will slow results but make it easier to filter if you're looking for a specific radio.
      '';
    };

    user = mkOption {
      type = types.str;
      default = null;
      description = ''
        User account under which both the service and the web-application run.
      '';
    };

    serveStaticSite = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Additionally, serve all client build
      '';
    };

    staticSiteServedOn = mkOption {
      type = types.int;
      default = 3336;
      description = ''
        Port for serving all client build
      '';
    };

    alwaysOnRadio = {
      enable = mkEnableOption ''
        an always-on radio: a muted mpv player started at login, kept alive
        by systemd and controlled through mpv's IPC socket with the `radio`
        CLI (on, off, toggle, status, stations, station NAME, pick). The
        station is looked up by name in the server's favorites, so it must
        be added to your favorites first. Linux only.
      '';

      defaultStation = mkOption {
        type = types.str;
        description = ''
          Name of the station (one of your favorites) the always-on radio
          starts playing.
        '';
      };

      socket = mkOption {
        type = types.str;
        default = "$XDG_RUNTIME_DIR/radio.sock";
        description = ''
          Path of the mpv IPC socket used to control the always-on radio.
        '';
      };

      audioOutput = mkOption {
        type = types.str;
        default = "pulse";
        description = ''
          mpv --ao value. `pulse` works for both PulseAudio and PipeWire
          (via pipewire-pulse).
        '';
      };

      picker = mkOption {
        type = types.listOf types.str;
        # keep in sync with the default in nix/radio-cli.nix
        default = [ "${pkgs.rofi}/bin/rofi" "-dmenu" "-i" "-matching" "fuzzy" "-p" "Radio" ];
        description = ''
          Command (with arguments) used by `radio pick` to select a
          station. Defaults to rofi; e.g. wofi users can set
          [ "wofi" "--show" "dmenu" ].
        '';
      };

      installCli = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to install the `radio` CLI into environment.systemPackages.
          Disable when you link the standalone `radio` package from this
          flake instead (installing both collides on bin/radio).
        '';
      };
    };

  };
}
