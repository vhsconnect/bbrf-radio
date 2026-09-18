# Builds the `radio-waybar` script: a one-shot JSON status of the bbrf
# always-on radio for waybar's custom module protocol:
#
#   {"text": ..., "class": "audible"|"muted"|"off", "tooltip": ...}
#
# Consumed by nix/waybar-module.nix (with the user's option values) and
# exposed as the standalone flake package `radio-waybar` so any
# environment can link it, e.g.
#   environment.systemPackages = [ bbrf-radio.packages.${system}.radio-waybar ];
# or customized:
#   bbrf-radio.packages.${system}.radio-waybar.override { defaultStation = "…"; };
{
  lib,
  writeScriptBin,
  fish,
  jq,
  socat,
  # --- parameters (module options / standalone defaults) ---
  socket ? "$XDG_RUNTIME_DIR/radio.sock",
  defaultStation ? "",
}:
writeScriptBin "radio-waybar" (
  builtins.concatStringsSep "\n" [
    ''
      #! ${fish}/bin/fish
      # SOCKET and DEFAULT_STATION can be overridden via the environment.
      set -q SOCKET; or set SOCKET "${socket}"
      set -q DEFAULT_STATION; or set DEFAULT_STATION "${defaultStation}"
      set JQ "${jq}/bin/jq"
      set SOCAT "${socat}/bin/socat"
    ''
    (builtins.readFile ./radio-waybar.fish)
  ]
)
