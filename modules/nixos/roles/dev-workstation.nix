{
  self,
  agentKitPackages,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.platformBlueprints.roles.devWorkstation;

  # nixos-modules entries resolve to this flake's own packages, which exist
  # only for the platforms they are built for (kotlin-lsp is x86_64-only), so
  # an entry this flake does not provide for the host is left out rather than
  # failing evaluation on, say, aarch64.
  ownPackages = self.packages.${pkgs.stdenv.hostPlatform.system} or {};
  resolve = entry:
    if entry.source == "nixos-modules"
    then ownPackages.${entry.attr} or null
    else lib.getAttrFromPath (lib.splitString "." entry.attr) pkgs;

  corePackages = builtins.filter (pkg: pkg != null) (builtins.map resolve agentKitPackages.core);
in {
  options.platformBlueprints.roles.devWorkstation = {
    enable = lib.mkEnableOption "dev workstation role: the toolchains, language servers and CLI tools agent-kit lists for NixOS";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = corePackages;
      readOnly = true;
      description = "Packages the role installs";
    };
  };

  # The package list comes from agent-kit's registry
  # (registry/generated/nixos/packages.nix), so tools are declared there, not
  # here.
  config = lib.mkIf cfg.enable {
    environment.systemPackages = cfg.packages;
  };
}
