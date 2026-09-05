{
  lib,
  mkPnpmPackage,
  makeWrapper,
  nodejs_26,
  # pnpm from pnpm2nix's own nixpkgs pin — the rewritten (file:/nix/store)
  # lockfile only works with the pnpm the fork is tested against; newer
  # pnpm (>= 10.13, incl. nixpkgs' pnpm_10) rejects it with
  # ERR_PNPM_RESOLUTION_SHAPE_MISMATCH in the offline sandbox.
  pnpm,
  ...
}:

mkPnpmPackage {
  src = ../.;
  packageJSON = ../package.json;
  pnpmLockYaml = ../pnpm-lock.yaml;

  nodejs = nodejs_26;
  inherit pnpm;

  scriptFull = ''
    pnpm run build
    pnpm run build:static
  '';

  noDevDependencies = true;
  installNodeModules = true;
  distDirIsOut = false;
  distDirs = [
    "server"
    "pages"
    "index.js"
    "index.html"
    "styles.css"
    "package.json"
  ];

  extraNativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    mkdir -p $out/bin
    makeWrapper ${nodejs_26}/bin/node $out/bin/bbrf-radio \
      --add-flags "$out/server/server.mjs"
  '';

  meta = with lib; {
    description = "browse, favorite and play online radios in your browser";
    homepage = "https://github.com/vhsconnect/bbrf-radio";
    license = licenses.gpl2Only;
    platforms = platforms.unix;
    mainProgram = "bbrf-radio";
  };
}
