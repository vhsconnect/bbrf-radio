{ pkgs ? import <nixpkgs> { } }:
let
  node18 = pkgs.nodejs_18;
in
pkgs.stdenv.mkDerivation {
  name = "web-shell";
  packages = [ node18 ];
  shellHook = "";
  buildInputs = [
    node18
    pkgs.node2nix
  ];
}
