{
  config,
  lib,
  ...
}: let
  cfg = config.platformBlueprints.unfree;
in {
  options.platformBlueprints.unfree.packages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Unfree package names (lib.getName) the enabled modules install. An entry ending in * is a name prefix (rocm* allows rocminfo); one ending in - is a prefix that keeps the hyphen (amdgpu-).";
  };

  # One module owns the predicate: two definitions of
  # nixpkgs.config.allowUnfreePredicate conflict, so every module appends only
  # the unfree packages it installs under its current settings.
  config = lib.mkIf (cfg.packages != []) {
    nixpkgs.config.allowUnfreePredicate = pkg: let
      name = lib.getName pkg;
    in
      builtins.any (
        allowed:
          name
          == allowed
          || (lib.hasSuffix "-" allowed && lib.hasPrefix allowed name)
          || (lib.hasSuffix "*" allowed && lib.hasPrefix (lib.removeSuffix "*" allowed) name)
      )
      cfg.packages;
  };
}
