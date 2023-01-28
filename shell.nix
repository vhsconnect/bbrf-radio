{ pkgs ? import <nixpkgs> { } }:
let
  nodeLTS = pkgs.nodejs;
in
pkgs.stdenv.mkDerivation {
  name = "web-shell";
  packages = [ nodeLTS ];
  shellHook = "";
  buildInputs = [ nodeLTS pkgs.node2nix ];
}
