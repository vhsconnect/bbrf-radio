flake: { config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.bbrf;
  inherit (flake.packages.${pkgs.stdenv.hostPlatform.system}) bbrf-radio;

in
{
  options.services.bbrf = {

    enable = mkEnableOption (mdDoc ''
      Browser, play and favorite internet radios in your browser.
    '');

    port = mkOption {
      type = types.int;
      default = 3335;
      description = ''
        The port the service should bind to.
      '';
    };
    faderValue = mkOption
      {
        type = types.int;
        default = 25;
        description = ''
          the fader value is the how long it takes in miliseconds to fade 1/100th bit of volume in each direction. Higher values fade the radios more slowly. Recommended values are between 15 and 50 ms. 

        '';

      };

    itemsPerPage = mkOption
      {
        type = types.int;
        default = 25;
        description = ''
          Items per page when returning results from radio list queries. Bigger limits will slow results but make it easier to filter if you're looking for a specific radio.
        '';

      };

    user = mkOption {
      type = types.str;
      default = null;
      description = lib.mdDoc ''
        User account under which both the service and the web-application run.
      '';
    };
  };

  config = mkIf cfg.enable {

    systemd.services.bbrf = {
      description = "bbrf-radio server";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${pkgs.bash}/bin/bash ${bbrf-radio}/bin/bbrf-radio";
      };
      preStart = ''
        SETTINGS_FILE=/home/${cfg.user}/.config/bbrf-radio/settings.json
        mkdir -p /home/${cfg.user}/.config/bbrf-radio
        cat <<EOF > $SETTINGS_FILE
         ${(builtins.toJSON {PORT = cfg.port; FADER_VALUE = cfg.faderValue; ITEMS_PER_PAGE = cfg.itemsPerPage; })}
        EOF
      '';
    };

  };
}
