# NixOS module for bbrf: systemd services, the always-on radio and the
# `radio` CLI. Import as `bbrf-radio.nixosModules.bbrf` (see flake.nix).
# Options live in nix/options.nix; nix-darwin users import
# `bbrf-radio.darwinModules.bbrf` instead.
flake:
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.bbrf;
  json = builtins.toJSON {
    PORT = cfg.port;
    FADER_VALUE = cfg.faderValue;
    ITEMS_PER_PAGE = cfg.itemsPerPage;
  };
  inherit (flake.packages.${pkgs.stdenv.hostPlatform.system}) bbrf-radio;

  # CLI controlling the always-on radio via mpv's IPC socket (fish).
  # Built by nix/radio-cli.nix (also exposed as the standalone flake
  # package `radio`) with this host's option values.
  radioCli = pkgs.callPackage ./radio-cli.nix {
    port = cfg.port;
    socket = cfg.alwaysOnRadio.socket;
    defaultStation = cfg.alwaysOnRadio.defaultStation;
    picker = cfg.alwaysOnRadio.picker;
  };
in
{
  imports = [ ./options.nix ];

  config = mkIf cfg.enable (mkMerge [

    {
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

      # historically started unconditionally when bbrf is enabled
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
    }

    (mkIf cfg.alwaysOnRadio.enable {
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

      environment.systemPackages = mkIf cfg.alwaysOnRadio.installCli [ radioCli ];
    })
  ]);
}
