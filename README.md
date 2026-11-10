# nixos-modules

Reusable NixOS modules and helper library for JorisJonkers-dev platform hosts.

## What It Is

This repository is a shared Nix artifact. It does not contain live host inventory, Flux cluster state, secrets, deploy nodes, disk layouts, or site-specific device paths.

## Flake Usage

Pin the flake in a consumer repository:

```nix
{
  inputs.nixos-modules.url = "github:JorisJonkers-dev/nixos-modules/v0.1.0";
}
```

Import modules in consumer-owned host modules:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.nixos-modules.nixosModules.default
    inputs.nixos-modules.nixosModules.roleK3sServer
    inputs.nixos-modules.nixosModules.roleLonghornNode
    inputs.nixos-modules.nixosModules.roleGpuAmd
    inputs.nixos-modules.nixosModules.serviceTailscale
  ];

  platformBlueprints.base = {
    enable = true;
    ssh.ports = [ 22 ];
    timeZone = "UTC";
    defaultLocale = "en_US.UTF-8";
  };

  platformBlueprints.roles.k3sServer.enable = true;
}
```

Available module outputs:

- `nixosModules.base`
- `nixosModules.k3s`
- `nixosModules.unfree`
- `nixosModules.default`
- `nixosModules.roleK3sBootstrap`
- `nixosModules.roleK3sServer`
- `nixosModules.roleK3sAgent`
- `nixosModules.roleTailscaleSubnetRouter`
- `nixosModules.roleLonghornNode`
- `nixosModules.roleGpuUtility`
- `nixosModules.roleGpuAmd`
- `nixosModules.roleGpuNvidia`
- `nixosModules.roleNodeLabelApplier`
- `nixosModules.roleDevWorkstation`
- `nixosModules.roleControlPlane`
- `nixosModules.roleWorker`
- `nixosModules.roleNetworkTailscale`
- `nixosModules.roleStorageLonghorn`
- `nixosModules.roleAcceleratorGpu`
- `nixosModules.serviceTailscale`
- `nixosModules.serviceMediaStorage`
- `nixosModules.serviceSamba`
- `nixosModules.serviceOllamaRocm`
- `nixosModules.serviceBtrfsBackupSnapshots`
- `nixosModules.hardwareAmdCpu`
- `nixosModules.hardwareLaptop`
- `nixosModules.hardwareRaspberryPiAarch64`
- `nixosModules.imageRaspberryPiSdImage`

## Reusable Roles

The role modules expose scheduling and host mechanics without carrying host
inventory:

- `platformBlueprints.roles.k3sServer` and `k3sAgent` configure generic k3s
  server or agent behavior.
- `platformBlueprints.roles.longhornNode` installs generic Longhorn
  prerequisites and storage node labels.
- `platformBlueprints.roles.gpuAmd` enables AMD graphics, ROCm utilities, and
  AMD GPU node labels. `mode = "apu"` keeps the graphics stack only;
  `mode = "discrete"` adds ROCm compute, overdrive and LACT.
- `platformBlueprints.roles.gpuNvidia` enables NVIDIA graphics, the container
  toolkit, and NVIDIA GPU node labels.
- `platformBlueprints.roles.nodeLabelApplier` applies caller-owned labels and
  taints with `kubectl`.
- `platformBlueprints.roles.devWorkstation` installs the toolchains, language
  servers and CLI tools agent-kit lists for NixOS. The list comes from
  agent-kit's registry (`registry/generated/nixos/packages.nix`, `core` group),
  so tools are declared there, not here.

Consumers own all sensitive inputs: node names, join tokens, device paths,
driver branch overrides, and any cluster-specific labels.

`platformBlueprints.unfree.packages` collects the unfree package names the
enabled modules install: an exact `lib.getName`, a prefix ending in `*`
(`rocm*` allows `rocminfo`), or a prefix ending in a hyphen (`amdgpu-`). One module owns `nixpkgs.config.allowUnfreePredicate` because two
definitions of it conflict, so roles append only their own names and the
predicate is set once the list is non-empty.

The `workstation-example` check (x86_64-linux only) builds an example
workstation that enables `platformBlueprints.roles.devWorkstation` and an
integrated-GPU `platformBlueprints.roles.gpuAmd`, so CI proves the non-gaming
stack evaluates and builds. The `gpu-amd-modes` check compares that APU host
against a discrete-card fixture: overdrive, LACT and the unfree ROCm names must
follow `mode`.

## Reusable Hardware

The hardware modules cover the machine itself rather than a role:

- `platformBlueprints.hardware.amdCpu` enables AMD microcode updates, the
  `amd_pstate` driver and `kvm-amd`.
- `platformBlueprints.hardware.laptop` enables power profiles, firmware
  updates, touchpad and suspend handling. `convertible.enable` adds the iio
  sensor GNOME uses for auto-rotate and tablet mode, and
  `batteryChargeThreshold` caps charging on firmware that supports it.

```nix
{
  imports = [
    inputs.nixos-modules.nixosModules.hardwareAmdCpu
    inputs.nixos-modules.nixosModules.hardwareLaptop
  ];

  platformBlueprints.hardware.amdCpu.enable = true;
  platformBlueprints.hardware.laptop = {
    enable = true;
    convertible.enable = true;
    batteryChargeThreshold = 80;
  };
}
```

The `hardware-laptop` check (x86_64-linux only) asserts those settings on the
example workstation and that a plain laptop leaves the convertible and
threshold parts off.

## Reusable Services

The service modules are parameterized building blocks:

```nix
{
  imports = [
    inputs.nixos-modules.nixosModules.serviceMediaStorage
    inputs.nixos-modules.nixosModules.serviceSamba
    inputs.nixos-modules.nixosModules.serviceBtrfsBackupSnapshots
  ];

  platformBlueprints.services.mediaStorage = {
    enable = true;
    owner = "media";
    group = "media";
    directories = [ "Completed" "Films" "Series" ];
    mounts."/srv/media" = {
      device = "/dev/disk/by-label/EXAMPLE_MEDIA";
      fsType = "btrfs";
    };
    viewBinds."library/Films" = "/srv/media/Films";
  };

  platformBlueprints.services.samba = {
    enable = true;
    users.media-root = "All-access media share identity";
    shares.media = {
      path = "/srv/media";
      browseable = "yes";
      "read only" = "no";
      "valid users" = "media-root";
    };
  };

  platformBlueprints.services.btrfsBackupSnapshots = {
    enable = true;
    sourceSubvolume = "/srv/media/Backup";
    sourceSnapshotDirectory = "/srv/media/.snapshots";
    destinationSnapshotDirectory = "/srv/backup/.snapshots/Backup";
  };
}
```

`serviceTailscale` enables the host Tailscale service and optional loose
reverse-path filtering. `serviceOllamaRocm` enables `pkgs.ollama-rocm` with
caller-owned listen address, model list, model directory, environment variables,
and firewall exposure.

## Fleet Helpers

Compatibility aliases are retained for `k3s-control-plane`, `k3s-worker`, and `tailscale-network`.

## Node Contract Labels

`lib.nodeContractLabels` builds canonical Kubernetes node labels under `platform.jorisjonkers.dev/*` and transition mirrors under `personal-stack/*`. Consumers pass inventory-owned node facts into the helper; this repository does not carry the inventory.

## Local Validation

```bash
nix flake check --print-build-logs
```

## Links

- [Organization profile](https://github.com/JorisJonkers-dev)
- [Security policy](https://github.com/JorisJonkers-dev/.github/security/policy)
- [Changelog](./CHANGELOG.md)
- [License](./LICENSE)

Copyright (c) Joris Jonkers. Source available for viewing only; use, copying,
modification, redistribution, deployment, or reuse is not licensed. See
[LICENSE](./LICENSE).
