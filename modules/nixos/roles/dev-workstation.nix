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

  resolve = entry:
    if entry.source == "nixos-modules"
    then self.packages.${pkgs.stdenv.hostPlatform.system}.${entry.attr}
    else lib.getAttrFromPath (lib.splitString "." entry.attr) pkgs;

  corePackages = builtins.map resolve agentKitPackages.core;
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
