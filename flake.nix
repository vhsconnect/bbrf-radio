{
  description = ''Browse, favorite and play online radios in your browser'';
  inputs = {
    nixpkgs.url = "github:nixOS/nixpkgs";
    utils.url = "github:numtide/flake-utils";
  };
  outputs =
    { self
    , nixpkgs
    , utils
    ,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.bbrf-radio = pkgs.callPackage ./package.nix { };
        defaultPackage = self.packages."${system}".bbrf-radio;
        nixosModules = rec {
          bbrf = import ./module.nix self;
          default = bbrf;
        };
      }
    );
}
