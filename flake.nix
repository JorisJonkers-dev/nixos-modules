{
  description = "Reusable NixOS modules and helpers for JorisJonkers-dev platform hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
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
  in {
    nixosModules = rec {
      base = ./modules/nixos/base.nix;
      k3s = ./modules/nixos/k3s.nix;

      roleK3sBootstrap = ./modules/nixos/roles/k3s-bootstrap.nix;
      roleK3sServer = ./modules/nixos/roles/k3s-server.nix;
      roleK3sAgent = ./modules/nixos/roles/k3s-agent.nix;
      roleTailscaleSubnetRouter = ./modules/nixos/roles/tailscale-subnet-router.nix;
      roleLonghornNode = ./modules/nixos/roles/longhorn-node.nix;
      roleGpuUtility = ./modules/nixos/roles/gpu-utility.nix;
      roleGpuAmd = ./modules/nixos/roles/gpu-amd.nix;
      roleGpuNvidia = ./modules/nixos/roles/gpu-nvidia.nix;
      roleNodeLabelApplier = ./modules/nixos/roles/node-label-applier.nix;

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

    checks = forAllSystems (
      system: let
        pkgs = mkPkgs system;
        fixture = moduleFixture system;
        fixtureDrvPath = builtins.unsafeDiscardStringContext fixture.config.system.build.toplevel.drvPath;
      in {
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
