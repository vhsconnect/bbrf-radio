{
  lib,
  config,
  dream2nix,
  ...
}:
{
  imports = [
    dream2nix.modules.dream2nix.nodejs-package-lock-v3
    dream2nix.modules.dream2nix.nodejs-granular-v3
  ];

  deps =
    { nixpkgs, ... }:
    {
      inherit (nixpkgs)
        gnugrep
        stdenv
        ;
    };

  mkDerivation = {
    src = ../.;
    preBuild = ''
      npm run build:static
    '';

    meta = with lib; {
      description = "browse, favorite and play online radios in your browser";
      homepage = "https://github.com/vhsconnect/bbrf-radio";
      license = licenses.gpl2Only;
      platforms = platforms.unix;
    };
  };

  nodejs-package-lock-v3 = {
    packageLockFile = "${config.mkDerivation.src}/package-lock.json";
  };

  name = "bbrf-radio";
  inherit (builtins.fromJSON (builtins.readFile ../package.json)) version;
}
