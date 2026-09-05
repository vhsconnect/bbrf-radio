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
    utils.lib.eachDefaultSystem (
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
        packages.bbrf-radio = callPackage ./nix/default.nix {
          pnpm = pnpm2nix.inputs.nixpkgs.legacyPackages.${system}.pnpm;
        };
        defaultPackage = self.packages."${system}".bbrf-radio;
        nixosModules = rec {
          bbrf = import ./nix/module.nix self system;
          default = bbrf;
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
