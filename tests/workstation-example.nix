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
      self.nixosModules.hardwareAmdCpu
      self.nixosModules.hardwareLaptop
      self.nixosModules.desktopGnome
      self.nixosModules.desktopTuning
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

          platformBlueprints.hardware.amdCpu.enable = true;
          platformBlueprints.hardware.laptop = {
            enable = true;
            convertible.enable = true;
            batteryChargeThreshold = 80;
          };

          platformBlueprints.desktop.gnome.enable = true;
          platformBlueprints.desktop.tuning = {
            enable = true;
            preset = "laptop";
          };
        }
      )
    ];
  }
