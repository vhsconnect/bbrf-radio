{ lib
, stdenv
, pkgs
, nodejs
, runtimeShell
}:

stdenv.mkDerivation {
  pname = "bbrf-radio";
  version = "0.7.4";
  src = builtins.path { path = ./.; name = "bbrf-radio"; };

  nativeBuildInputs = [
    nodejs
  ];

  buildPhase =
    let
      nodeDependencies = (import ./default.nix {
        inherit pkgs nodejs;
        inherit (stdenv.hostPlatform) system;
      }).nodeDependencies.override (_: {
        dontNpmInstall = true;
      });
    in
    ''
      runHook preBuild
      export PATH="${nodeDependencies}/bin:${nodejs}/bin:$PATH"
      ln -s ${nodeDependencies}/lib/node_modules .
      npm run build
      runHook postBuild
    '';

  postInstall = ''
    mkdir -p $out/bin
    mv * $out
    cat <<EOF > $out/bin/bbrf-radio
    #!${runtimeShell}
    exec ${nodejs}/bin/node $out/server/server.mjs
    EOF
    chmod +x $out/bin/bbrf-radio
  '';

  installPhase = ''
    runHook preInstall
    runHook postInstall
  '';

  meta = with lib; {
    description = "browse, favorite and play online radios in your browser";
    homepage = "https://github.com/vhsconnect/bbrf-radio";
    license = licenses.gpl2Only;
    maintainers = with maintainers; [ vhsconnect ];
    platforms = platforms.unix;
  };
}
