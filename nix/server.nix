{
  lib,
  beamPackages,
  runCommand,
  # the frontend bundle comes from the pnpm package (nix/default.nix)
  bbrf-radio,
}:

let
  pname = "bbrf";
  version = "0.11.0";
  src = lib.fileset.toSource {
    root = ../server-next;
    fileset = lib.fileset.unions [
      ../server-next/mix.exs
      ../server-next/mix.lock
      ../server-next/config
      ../server-next/lib
      ../server-next/priv
    ];
  };

  # copied, not linked, so the closure does not hold the node server and its node_modules
  static = runCommand "bbrf-static-${version}" { } ''
    mkdir -p $out
    cp ${bbrf-radio}/index.js ${bbrf-radio}/index.html ${bbrf-radio}/styles.css ${../favicon-16x16.png} $out/
    mv $out/*-favicon-16x16.png $out/favicon-16x16.png
  '';
in
beamPackages.mixRelease {
  inherit pname version src;

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "${pname}-deps";
    inherit version src;
    hash = "sha256-wT7nF7k4dKY4w4SB61iTM1Ma6njGBqn7cOV01G847GE=";
  };

  # exqlite would download a precompiled NIF, which the sandbox forbids
  postPatch = ''
    echo 'config :exqlite, force_build: true' >> config/config.exs
  '';

  postInstall = ''
    ln -s ${static} $out/static
  '';

  passthru = { inherit static; };

  meta = {
    description = "browse, favorite and play online radios in your browser";
    homepage = "https://github.com/vhsconnect/bbrf-radio";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.unix;
    mainProgram = "bbrf";
  };
}
