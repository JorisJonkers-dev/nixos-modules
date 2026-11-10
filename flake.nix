{
  description = "Reusable NixOS modules and helpers for JorisJonkers-dev platform hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agent-kit.url = "github:JorisJonkers-dev/agent-kit";
    agent-kit.flake = false;
  };

  outputs = {
    self,
    nixpkgs,
    agent-kit,
  }: let
    lib = nixpkgs.lib;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = lib.genAttrs systems;
    mkPkgs = system: import nixpkgs {inherit system;};
    moduleFixture = system:
      import ./tests/module-fixture.nix {
        inherit self nixpkgs system;
      };
    agentKitPackages = import "${agent-kit}/registry/generated/nixos/packages.nix";
    devWorkstationRole = import ./modules/nixos/roles/dev-workstation.nix {
      inherit self agentKitPackages;
    };
  in {
    nixosModules = rec {
      base = ./modules/nixos/base.nix;
      k3s = ./modules/nixos/k3s.nix;
      unfree = ./modules/nixos/unfree.nix;

      roleK3sBootstrap = ./modules/nixos/roles/k3s-bootstrap.nix;
      roleK3sServer = ./modules/nixos/roles/k3s-server.nix;
      roleK3sAgent = ./modules/nixos/roles/k3s-agent.nix;
      roleTailscaleSubnetRouter = ./modules/nixos/roles/tailscale-subnet-router.nix;
      roleLonghornNode = ./modules/nixos/roles/longhorn-node.nix;
      roleGpuUtility = ./modules/nixos/roles/gpu-utility.nix;
      roleGpuAmd = ./modules/nixos/roles/gpu-amd.nix;
      roleGpuNvidia = ./modules/nixos/roles/gpu-nvidia.nix;
      roleNodeLabelApplier = ./modules/nixos/roles/node-label-applier.nix;
      roleDevWorkstation = devWorkstationRole;

      serviceTailscale = ./modules/nixos/services/tailscale.nix;
      serviceMediaStorage = ./modules/nixos/services/media-storage.nix;
      serviceSamba = ./modules/nixos/services/samba.nix;
      serviceOllamaRocm = ./modules/nixos/services/ollama-rocm.nix;
      serviceBtrfsBackupSnapshots = ./modules/nixos/services/btrfs-backup-snapshots.nix;

      roleControlPlane = roleK3sServer;
      roleWorker = roleK3sAgent;
      roleNetworkTailscale = roleTailscaleSubnetRouter;
      roleStorageLonghorn = roleLonghornNode;
      roleAcceleratorGpu = roleGpuUtility;
      roleGpuAMD = roleGpuAmd;
      roleGpuNVIDIA = roleGpuNvidia;

      hardwareRaspberryPiAarch64 = ./modules/nixos/hardware/raspberry-pi-aarch64.nix;
      imageRaspberryPiSdImage = ./modules/nixos/image/raspberry-pi-sd-image.nix;

      roles = {
        k3sBootstrap = roleK3sBootstrap;
        k3sServer = roleK3sServer;
        k3sAgent = roleK3sAgent;
        tailscaleSubnetRouter = roleTailscaleSubnetRouter;
        longhornNode = roleLonghornNode;
        gpuUtility = roleGpuUtility;
        gpuAmd = roleGpuAmd;
        gpuNvidia = roleGpuNvidia;
        nodeLabelApplier = roleNodeLabelApplier;
        devWorkstation = devWorkstationRole;
        controlPlane = roleControlPlane;
        worker = roleWorker;
        networkTailscale = roleNetworkTailscale;
        storageLonghorn = roleStorageLonghorn;
        acceleratorGpu = roleAcceleratorGpu;
      };

      services = {
        tailscale = serviceTailscale;
        mediaStorage = serviceMediaStorage;
        samba = serviceSamba;
        ollamaRocm = serviceOllamaRocm;
        btrfsBackupSnapshots = serviceBtrfsBackupSnapshots;
      };

      platform = {
        unfree = unfree;
      };

      default = {
        imports = [
          base
          k3s
        ];
      };
    };

    lib = {
      nodeContractLabels = import ./lib/nixos/node-contract-labels.nix {
        inherit lib;
      };
    };

    overlays.default = final: _prev: {
      kotlin-lsp = final.callPackage ./pkgs/kotlin-lsp/package.nix {};
    };

    # The upstream binary distribution is x86_64-linux only.
    packages.x86_64-linux.kotlin-lsp = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfreePredicate = pkg: lib.getName pkg == "kotlin-lsp";
      };
    in
      pkgs.callPackage ./pkgs/kotlin-lsp/package.nix {};

    checks = forAllSystems (
      system: let
        pkgs = mkPkgs system;
        fixture = moduleFixture system;
        fixtureDrvPath = builtins.unsafeDiscardStringContext fixture.config.system.build.toplevel.drvPath;
      in
        (lib.optionalAttrs (system == "x86_64-linux") {
          workstation-example = let
            workstation = import ./tests/workstation-example.nix {
              inherit self nixpkgs;
              system = "x86_64-linux";
            };
            rolePackages = workstation.config.platformBlueprints.roles.devWorkstation.packages;
            installedOutPaths = builtins.map (pkg: pkg.outPath) workstation.config.environment.systemPackages;
            corePackages = lib.zipListsWith (entry: pkg: {inherit entry pkg;}) agentKitPackages.core rolePackages;
            missingCore =
              lib.findFirst ({pkg, ...}: !builtins.elem pkg.outPath installedOutPaths)
              null
              corePackages;
          in
            # x86_64 provides every core entry, so the lists line up one to one;
            # a shorter list would make zipListsWith skip entries silently.
            assert lib.assertMsg (builtins.length rolePackages == builtins.length agentKitPackages.core) "devWorkstation resolved ${toString (builtins.length rolePackages)} of ${toString (builtins.length agentKitPackages.core)} core packages";
            assert lib.assertMsg (missingCore == null) "workstation-example must install agent-kit core package ${missingCore.entry.attr}";
            # References the built toplevel, unlike module-fixture's drvPath,
            # so `nix flake check` builds the whole example workstation.
              pkgs.runCommand "nixos-modules-workstation-example" {} ''
                ln -s ${workstation.config.system.build.toplevel} "$out"
              '';

          gpu-amd-modes = let
            apu = import ./tests/workstation-example.nix {
              inherit self nixpkgs;
              system = "x86_64-linux";
            };
            discrete = lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                self.nixosModules.roleGpuAmd
                (
                  {...}: {
                    boot.loader.grub.enable = false;
                    fileSystems."/".device = "gpu-amd-discrete-root";
                    fileSystems."/".fsType = "ext4";
                    system.stateVersion = "25.05";

                    platformBlueprints.roles.gpuAmd = {
                      enable = true;
                      mode = "discrete";
                    };
                  }
                )
              ];
            };
            apuUnfree = apu.config.platformBlueprints.unfree.packages;
            discreteUnfree = discrete.config.platformBlueprints.unfree.packages;
            isRocmName = name: lib.hasPrefix "rocm" name || lib.hasPrefix "hip" name;
          in
            # An APU has no compute queue, so ROCm, overdrive and LACT must stay
            # off and must not pull unfree compute packages into the predicate.
            assert lib.assertMsg (!apu.config.hardware.amdgpu.overdrive.enable) "gpu-amd-modes: an APU must not enable amdgpu overdrive";
            assert lib.assertMsg (!apu.config.services.lact.enable) "gpu-amd-modes: an APU must not enable LACT";
            assert lib.assertMsg (builtins.filter isRocmName apuUnfree == []) "gpu-amd-modes: an APU must not allow unfree ROCm packages";
            assert lib.assertMsg discrete.config.hardware.amdgpu.overdrive.enable "gpu-amd-modes: a discrete card must enable amdgpu overdrive";
            assert lib.assertMsg discrete.config.services.lact.enable "gpu-amd-modes: a discrete card must enable LACT";
            assert lib.assertMsg (builtins.any (name: lib.hasPrefix "rocm" name) discreteUnfree) "gpu-amd-modes: a discrete card must allow unfree ROCm packages";
            # The prefixes must reach the predicate as prefixes: rocminfo and
            # hipblas are separate packages, and an exact match would refuse them.
            assert lib.assertMsg (discrete.config.nixpkgs.config.allowUnfreePredicate {name = "rocminfo-6.4.3";}) "gpu-amd-modes: the predicate must allow rocminfo on a discrete card";
            assert lib.assertMsg (discrete.config.nixpkgs.config.allowUnfreePredicate {name = "hipblas-6.4.3";}) "gpu-amd-modes: the predicate must allow hipblas on a discrete card";
            assert lib.assertMsg (!(discrete.config.nixpkgs.config.allowUnfreePredicate {name = "steam-1.0";})) "gpu-amd-modes: the predicate must refuse packages nobody allowed";
              pkgs.runCommand "nixos-modules-gpu-amd-modes" {} "touch $out";
        })
        // {
          module-fixture = pkgs.runCommand "nixos-modules-module-fixture" {} ''
            printf '%s\n' '${fixtureDrvPath}' > "$out"
          '';
          # Requires= would let a tailscaled restart stop k3s and leave it stopped.
          k3s-soft-dependencies = let
            k3s = fixture.config.systemd.services.k3s;
          in
            assert lib.assertMsg (builtins.elem "network-online.target" k3s.wants) "k3s must Want its requiredServices";
            assert lib.assertMsg (!(builtins.elem "network-online.target" k3s.requires)) "k3s must not Require its requiredServices";
              pkgs.runCommand "nixos-modules-k3s-soft-dependencies" {} "touch $out";
        }
    );
  };
}
