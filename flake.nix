{
  description = ''Browse, favorite and play online radios in your browser'';
  inputs = {
    pnpm2nix.url = "github:FliegendeWurst/pnpm2nix-nzbr";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      pnpm2nix,
      utils,
    }:
    {
      # System-independent: nix/module.nix derives the system from
      # pkgs.stdenv.hostPlatform, so consumers import
      # bbrf-radio.nixosModules.bbrf on any system.
      nixosModules = rec {
        bbrf = import ./nix/module.nix self;
        bbrf-waybar = import ./nix/waybar-module.nix;
        default = [
          bbrf
          bbrf-waybar
        ];
      };
    }
    // utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
          pnpm2nix.overlays.default
        ];
        node22 = pkgs.nodejs_22;
        typescript = pkgs.typescript;
      in
      with pkgs;
      {
        packages = rec {
          bbrf-radio = callPackage ./nix/default.nix {
            pnpm = pnpm2nix.inputs.nixpkgs.legacyPackages.${system}.pnpm;
          };
          # Standalone `radio` CLI with the alwaysOnRadio defaults;
          # override port/socket/defaultStation/picker via .override.
          radio = callPackage ./nix/radio-cli.nix { };
          # Standalone waybar status script; override
          # socket/defaultStation via .override.
          radio-waybar = callPackage ./nix/radio-waybar.nix { };
          default = bbrf-radio;
        };
        devShells.default = mkShell {
          buildInputs = [
            node22
            typescript
            pnpm_10
          ];
        };
      }
    );
}
