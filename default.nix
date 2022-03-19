
{ pkgs ? import <nixpkgs> { } }:
let
  mynode = pkgs.nodejs-17_x;
in
pkgs.stdenv.mkDerivation {
  name = "web-shell";
  packages = [ mynode ];
  shellHook = "";
  buildInputs = [ mynode ];
}
