{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zlib,
  jdk25_headless,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "kotlin-lsp";
  version = "263.7084.0";

  src = fetchurl {
    url = "https://download.jetbrains.com/language-server/kotlin-server/${finalAttrs.version}/kotlin-server-${finalAttrs.version}.tar.gz";
    sha256 = "ae0c4b01e17ab73a4a5227a78ea99e6dcbe3e499600315b22759a4e4cddd11df";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    zlib
    stdenv.cc.cc.lib
  ];

  # The bundled JetBrains Runtime is replaced by a nixpkgs JDK below, so
  # bin/intellij-server is the only ELF file left for autoPatchelfHook to patch.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin
    cp -r . $out/lib/kotlin-lsp

    # The launcher resolves its runtime from ./jbr next to bin/, so point that
    # at a NixOS-built JDK instead of shipping the bundled dynamically linked
    # copy. The server's classes need Java 25 (class file version 69);
    # nixpkgs' JetBrains Runtime is still 21, so plain OpenJDK 25 it is.
    rm -rf $out/lib/kotlin-lsp/jbr
    ln -s ${jdk25_headless}/lib/openjdk $out/lib/kotlin-lsp/jbr

    # Deprecated bash wrapper; the wrapped launcher replaces it.
    rm $out/lib/kotlin-lsp/kotlin-lsp.sh

    makeWrapper $out/lib/kotlin-lsp/bin/intellij-server $out/bin/kotlin-lsp

    runHook postInstall
  '';

  meta = {
    description = "Kotlin language server from JetBrains";
    homepage = "https://github.com/Kotlin/kotlin-lsp";
    license = lib.licenses.unfree;
    sourceProvenance = [
      lib.sourceTypes.binaryNativeCode
      lib.sourceTypes.binaryBytecode
    ];
    platforms = ["x86_64-linux"];
    mainProgram = "kotlin-lsp";
  };
})
