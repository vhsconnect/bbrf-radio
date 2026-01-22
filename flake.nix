{
  description = ''Browse, favorite and play online radios in your browser'';
  inputs = {
    dream2nix.url = "github:nix-community/dream2nix";
    utils.url = "github:numtide/flake-utils";
    nixpkgs.follows = "dream2nix/nixpkgs";
  };
  outputs =
    {
      self,
      dream2nix,
      nixpkgs,
      utils,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        node22 = pkgs.nodejs_22;
        typescript = pkgs.typescript;
      in
      with pkgs;
      {
        packages.bbrf-radio = dream2nix.lib.evalModules {
          packageSets.nixpkgs = pkgs;
          modules = [
            ./nix/default.nix
            {
              paths.projectRoot = ./.;
              paths.projectRootFile = "flake.nix";
              paths.package = ./.;
            }
          ];
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
          ];
        };
      }
    );
}
