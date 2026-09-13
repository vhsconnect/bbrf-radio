flake: system:
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.bbrf;
  isDarwin = system: (system == "x86_64-darwin") || (system == "aarch64-darwin");
  json = builtins.toJSON {
    PORT = cfg.port;
    FADER_VALUE = cfg.faderValue;
    ITEMS_PER_PAGE = cfg.itemsPerPage;
  };
  inherit (flake.packages.${pkgs.stdenv.hostPlatform.system}) bbrf-radio;

  # CLI controlling the always-on radio via mpv's IPC socket (fish).
  radioCli = pkgs.writeScriptBin "radio" (
    builtins.concatStringsSep "\n" [
      ''
        #! ${pkgs.fish}/bin/fish
        set -q SOCKET; or set SOCKET "${cfg.alwaysOnRadio.socket}"
        set PORT "${toString cfg.port}"
        set DEFAULT_STATION "${cfg.alwaysOnRadio.defaultStation}"
        set CURL "${pkgs.curl}/bin/curl"
        set JQ "${pkgs.jq}/bin/jq"
        set SOCAT "${pkgs.socat}/bin/socat"
        set SORT "${pkgs.coreutils}/bin/sort"
      ''
      (builtins.readFile ./radio-cli.fish)
    ]
  );
in
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
    };

  };

  config = mkIf cfg.enable (mkMerge [

    (optionalAttrs (isDarwin system) {
      launchd.user.agents.bbrf = {
        script = ''
          SETTINGS_FILE=/Users/${cfg.user}/Library/Preferences/bbrf-radio/settings.json
          mkdir -p /Users/${cfg.user}/Library/Preferences/bbrf-radio
          cat <<EOF > $SETTINGS_FILE
          ${json}
          EOF
          exec ${bbrf-radio}/bin/bbrf-radio

        '';
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "/Users/${cfg.user}/Library/Logs/bbrf.out.log";
          StandardErrorPath = "/Users/${cfg.user}/Library/Logs/bbrf.err.log";
        };
      };

    })

    (optionalAttrs ((isDarwin system) && (cfg.serveStaticSite)) {
      launchd.user.agents.bbrf = {
        script = ''
          ${pkgs.python314}/bin/python -m http.server --directory ${bbrf-radio}/pages ${cfg.staticsiteservedon}

        '';
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "/Users/${cfg.user}/Library/Logs/bbrf-static.out.log";
          StandardErrorPath = "/Users/${cfg.user}/Library/Logs/bbrf-static.err.log";
        };
      };

    })

    (optionalAttrs (!(isDarwin system)) {

      systemd.services.bbrf = {
        description = "bbrf-radio server";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          ExecStart = "${bbrf-radio}/bin/bbrf-radio";
        };
        preStart = ''
          SETTINGS_FILE=/home/${cfg.user}/.config/bbrf-radio/settings.json
          mkdir -p /home/${cfg.user}/.config/bbrf-radio
          cat <<EOF > $SETTINGS_FILE
          ${json}
          EOF
        '';
      };

    })

    (optionalAttrs (!((isDarwin system) && cfg.serveStaticSite)) {

      systemd.services.bbrf-static = {
        description = "bbrf-radio static";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          ExecStart = "${pkgs.python314}/bin/python -m http.server --directory ${bbrf-radio}/pages ${builtins.toString cfg.staticSiteServedOn}";
        };
        preStart = ''
          SETTINGS_FILE=/home/${cfg.user}/.config/bbrf-radio/settings.json
          mkdir -p /home/${cfg.user}/.config/bbrf-radio
          cat <<EOF > $SETTINGS_FILE
          ${json}
          EOF
        '';
      };
    })

    (optionalAttrs (!(isDarwin system)) (mkIf cfg.alwaysOnRadio.enable {
      # the user service has to survive logout to be really "always on"
      users.users.${cfg.user}.linger = mkDefault true;

      systemd.user.services.radio = {
        description = "bbrf always-on radio (muted mpv, IPC-controlled)";
        wantedBy = [ "default.target" ];
        wants = [ "pipewire.service" ];
        after = [ "pipewire.service" ];

        startLimitIntervalSec = 0; # restart forever, really "always on"

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
        };

        script = ''
          until RADIO_URL=$(${pkgs.curl}/bin/curl -s http://localhost:${toString cfg.port}/favorites | ${pkgs.jq}/bin/jq -e -r --arg NAME "${cfg.alwaysOnRadio.defaultStation}" '.[] | select(.name == $NAME) | .url'); do
            echo "Waiting for bbrf endpoint..."
            ${pkgs.coreutils}/bin/sleep 2
          done

          exec ${pkgs.mpv}/bin/mpv \
            --no-video \
            --ao=${cfg.alwaysOnRadio.audioOutput} \
            --mute=yes \
            --cache-secs=10 \
            --audio-client-name=bbrf-radio \
            --msg-level=all=error \
            --input-ipc-server="${cfg.alwaysOnRadio.socket}" \
            "$RADIO_URL"
        '';
      };

      environment.systemPackages = [ radioCli ];
    }))
  ]);
}
