{
  lib,
  runCommand,
  makeWrapper,
  fish,
  openssl,
  sops,
  age,
  ssh-to-age,
  openssh,
}:

runCommand "bbrf-secrets"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta.mainProgram = "bbrf-secrets";
  }
  ''
    mkdir -p $out/bin
    makeWrapper ${lib.getExe fish} $out/bin/bbrf-secrets \
      --add-flags "--no-config ${../scripts/secrets.fish}" \
      --prefix PATH : ${
        lib.makeBinPath [
          openssl
          sops
          age
          ssh-to-age
          openssh
        ]
      }
  ''
