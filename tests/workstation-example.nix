{
  self,
  nixpkgs,
  system,
}: let
  lib = nixpkgs.lib;
in
  lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.roleDevWorkstation
      self.nixosModules.roleGpuAmd
      (
        {...}: {
          # Stands in for a real workstation: no hardware, no disks, so CI
          # proves the non-gaming stack evaluates and builds.
          boot.loader.grub.enable = false;
          fileSystems."/".device = "workstation-example-root";
          fileSystems."/".fsType = "ext4";
          system.stateVersion = "25.05";

          platformBlueprints.roles.devWorkstation.enable = true;

          # An integrated GPU: the graphics stack only, no ROCm compute.
          platformBlueprints.roles.gpuAmd = {
            enable = true;
            mode = "apu";
          };
        }
      )
    ];
  }
