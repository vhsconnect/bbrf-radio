{
  description = "Browse, favorite and play online radios in your browser";
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
        # nixpkgs' beam package sets still default to Elixir 1.18
        beamPackages = pkgs.beam28Packages.overrideScope (_final: prev: { elixir = prev.elixir_1_20; });
      in
      with pkgs;
      {
        packages = rec {
          bbrf-radio = callPackage ./nix/default.nix {
            pnpm = pnpm2nix.inputs.nixpkgs.legacyPackages.${system}.pnpm;
          };
          bbrf = callPackage ./nix/server.nix {
            inherit bbrf-radio beamPackages;
          };
          bbrf-secrets = callPackage ./nix/secrets.nix { };
          default = bbrf;
        };
        apps.secrets = {
          type = "app";
          program = lib.getExe self.packages.${system}.bbrf-secrets;
        };
        devShells.default = mkShell {
          buildInputs = [
            node22
            typescript
            pnpm_10
            beamPackages.erlang
            beamPackages.elixir
            # built on the Elixir above; nvim prefers the elixir-ls on $PATH
            beamPackages.elixir-ls
            sqlite
            # scripts/launch.fish and scripts/secrets.fish
            fish
            openssl
            sops
            age
            ssh-to-age
          ];
        };
      }
    )
    // {
      nixosModules = rec {
        bbrf = import ./nix/module.nix self;
        default = bbrf;
      };
    };
}
