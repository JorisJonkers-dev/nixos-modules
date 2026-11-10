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
      self.nixosModules.base
      self.nixosModules.k3s
      self.nixosModules.roleK3sBootstrap
      self.nixosModules.roleK3sServer
      self.nixosModules.roleK3sAgent
      self.nixosModules.roleTailscaleSubnetRouter
      self.nixosModules.roleLonghornNode
      self.nixosModules.roleGpuUtility
      self.nixosModules.roleGpuAmd
      self.nixosModules.roleGpuNvidia
      self.nixosModules.roleNodeLabelApplier
      self.nixosModules.serviceTailscale
      self.nixosModules.serviceMediaStorage
      self.nixosModules.serviceSamba
      self.nixosModules.serviceOllamaRocm
      self.nixosModules.serviceBtrfsBackupSnapshots
      self.nixosModules.hardwareRaspberryPiAarch64
      (
        {pkgs, ...}: {
          boot.loader.grub.enable = false;
          fileSystems."/".device = "fixture-root";
          fileSystems."/".fsType = "ext4";
          system.stateVersion = "25.05";

          platformBlueprints.base = {
            enable = true;
            ssh.ports = [22];
            deployUser = {
              enable = true;
              name = "deploy";
              authorizedKeys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureKeyMaterialOnly000000000000000000000"
              ];
              passwordlessSudo = true;
            };
            resolver = {
              nameservers = ["RESOLVER_ADDRESS"];
              options = [
                "timeout:1"
                "attempts:2"
              ];
            };
            timeZone = "UTC";
            defaultLocale = "en_US.UTF-8";
          };

          platformBlueprints.roles.k3sServer = {
            enable = true;
            oidc = {
              issuerUrl = "OIDC_ISSUER_URL";
              clientId = "dashboard";
              groupsClaim = "groups";
            };
          };

          platformBlueprints.k3s = {
            flannelInterface = "mesh0";
            waitForInterface.name = "mesh0";
            requiredServices = ["network-online.target"];
            nodeLabels.role = "fixture";
            nodeTaints = ["fixture=true:NoSchedule"];
          };

          platformBlueprints.roles.k3sBootstrap = {
            enable = true;
            flannelInterface = "mesh0";
            waitForInterface = true;
            nodeLabels.bootstrap = "fixture";
          };

          platformBlueprints.roles.tailscaleSubnetRouter = {
            enable = true;
            advertiseRoutes = ["10.42.0.0/16"];
            useForK3sFlannel = true;
            waitForK3s = true;
          };

          platformBlueprints.roles.longhornNode = {
            enable = true;
            enableOpenIscsi = false;
            enableNfsClient = false;
            installUtilities = false;
          };

          platformBlueprints.roles.gpuUtility = {
            enable = true;
            gpuVendors = ["amd"];
            installUtilities = false;
          };

          # The role is imported but not enabled here; the mode is pinned so
          # the fixture stays on the discrete defaults if it is turned on.
          platformBlueprints.roles.gpuAmd = {
            mode = "discrete";
          };

          platformBlueprints.services.tailscale = {
            enable = true;
            extraUpFlags = ["--accept-dns=false"];
          };

          platformBlueprints.services.mediaStorage = {
            enable = true;
            owner = "deploy";
            group = "deploy";
            directories = [
              "Completed"
              "Films"
              "Series"
            ];
            appStateRoot = "/var/lib/media-services";
            appStateDirectories = ["example-app"];
            viewsRoot = "/srv/media-views";
            viewBinds.library = "/srv/media/Films";
            scratch = {
              path = "/srv/media-scratch";
              nodatacow = true;
            };
          };

          platformBlueprints.services.samba = {
            enable = true;
            openFirewall = false;
            users.media-root = "All-access fixture share identity";
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

          platformBlueprints.roles.nodeLabelApplier = {
            enable = true;
            labels = self.lib.nodeContractLabels.mkNodeLabels {
              nodeName = "fixture-node";
              site = "fixture-site";
              roles = ["k3s-server"];
              capabilities = [
                "gpu"
                "storage-longhorn"
              ];
              gpuVendors = ["amd"];
            };
          };

          environment.systemPackages = [pkgs.hello];
        }
      )
    ];
  }
