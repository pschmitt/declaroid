{
  lib,
  stdenvNoCC,
  makeWrapper,
  android-tools,
  yq-go,
  curl,
  jq,
  coreutils,
  gnugrep,
  gawk,
  gnused,
  findutils,
  util-linux,
  gplaydl,
  fdroidcl,
}:

stdenvNoCC.mkDerivation {
  pname = "declaroid";
  version = "0.1.0";

  src = ../..;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 declaroid "$out/bin/declaroid"
    install -Dm644 completions/_declaroid "$out/share/zsh/site-functions/_declaroid"
    wrapProgram "$out/bin/declaroid" \
      --prefix PATH : ${
        lib.makeBinPath [
          android-tools
          yq-go
          curl
          jq
          coreutils
          gnugrep
          gawk
          gnused
          findutils
          util-linux
          gplaydl
          fdroidcl
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Declarative Android app provisioning via adb, gplaydl, fdroidcl, and GitHub releases";
    homepage = "https://github.com/pschmitt/declaroid";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "declaroid";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
