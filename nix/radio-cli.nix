# Builds the `radio` CLI: a fish script controlling the bbrf always-on
# radio through mpv's IPC socket.
#
# Consumed by nix/module.nix (with the user's option values) and exposed
# as the standalone flake package `radio` (with the defaults below) so
# any environment can link it, e.g.
#   environment.systemPackages = [ bbrf-radio.packages.${system}.radio ];
# or customized:
#   bbrf-radio.packages.${system}.radio.override { defaultStation = "…"; };
{
  lib,
  writeScriptBin,
  fish,
  curl,
  jq,
  socat,
  coreutils,
  rofi,
  # --- parameters (module options / standalone defaults) ---
  port ? 3335,
  socket ? "$XDG_RUNTIME_DIR/radio.sock",
  defaultStation ? "",
  # keep in sync with services.bbrf.alwaysOnRadio.picker in nix/module.nix
  picker ? [
    "${rofi}/bin/rofi"
    "-dmenu"
    "-i"
    "-matching"
    "fuzzy"
    "-p"
    "Radio"
  ],
}:
writeScriptBin "radio" (
  builtins.concatStringsSep "\n" [
    ''
      #! ${fish}/bin/fish
      # SOCKET, PORT and DEFAULT_STATION can be overridden via the environment.
      set -q SOCKET; or set SOCKET "${socket}"
      set -q PORT; or set PORT "${toString port}"
      set -q DEFAULT_STATION; or set DEFAULT_STATION "${defaultStation}"
      set CURL "${curl}/bin/curl"
      set JQ "${jq}/bin/jq"
      set SOCAT "${socat}/bin/socat"
      set SORT "${coreutils}/bin/sort"
      set PICKER ${lib.concatStringsSep " " picker}
    ''
    (builtins.readFile ./radio-cli.fish)
  ]
)
