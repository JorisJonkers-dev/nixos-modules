{
  lib,
  stdenvNoCC,
  fetchurl,
}:
# OpenCode 2, from the upstream release binary. agent-kit installs it only with
# Homebrew, and nixpkgs' source build fails at this pin (its node_modules hash
# no longer matches). The binary is a Bun executable with its program appended
# to the file, so it must not be stripped or patchelf'd; nix-ld provides the
# glibc loader it asks for (the devWorkstation role enables it).
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "2.2.6";

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${finalAttrs.version}/opencode-linux-x64.tar.gz";
    # From the release's SHA256SUMS.
    hash = "sha256-CLsh1jJs50DZHM5+voimU2kz9uHjA1O5GgawHyXaMGw=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode $out/bin/opencode
    runHook postInstall
  '';

  meta = {
    description = "OpenCode 2, the open-source terminal coding agent";
    homepage = "https://github.com/anomalyco/opencode";
    license = lib.licenses.mit;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = ["x86_64-linux"];
    mainProgram = "opencode";
  };
})
