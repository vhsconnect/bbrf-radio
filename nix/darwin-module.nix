# nix-darwin module for bbrf: launchd agents instead of systemd.
# Import as `bbrf-radio.darwinModules.bbrf` (see flake.nix).
# Options live in nix/options.nix. The always-on radio (systemd user
# service + `radio` CLI install) is Linux only; link the standalone
# `radio` package yourself if you want the CLI on darwin.
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
in
{
  imports = [ ./options.nix ];

  config = mkIf cfg.enable (mkMerge [

    {
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
    }

    (mkIf cfg.serveStaticSite {
      launchd.user.agents.bbrf = {
        script = ''
          ${pkgs.python314}/bin/python -m http.server --directory ${bbrf-radio}/pages ${builtins.toString cfg.staticSiteServedOn}

        '';
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "/Users/${cfg.user}/Library/Logs/bbrf-static.out.log";
          StandardErrorPath = "/Users/${cfg.user}/Library/Logs/bbrf-static.err.log";
        };
      };
    })
  ]);
}
