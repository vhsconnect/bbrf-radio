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
  ]);
}
