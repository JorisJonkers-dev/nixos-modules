{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.platformBlueprints.k3s;
  effectiveRole =
    if cfg.role != null
    then cfg.role
    else config.services.k3s.role;
  isAgent = effectiveRole == "agent";
  isServer = effectiveRole == "server";
  tokenDirectory =
    if cfg.joinTokenFile != null
    then builtins.dirOf cfg.joinTokenFile
    else null;
  labelFlags = lib.mapAttrsToList (name: value: "--node-label=${name}=${value}") cfg.nodeLabels;
  taintFlags = map (taint: "--node-taint=${taint}") cfg.nodeTaints;
  flannelFlags = lib.optional (cfg.flannelInterface != null) "--flannel-iface=${cfg.flannelInterface}";
  agentFlags =
    lib.optionals (cfg.joinTokenFile != null) ["--token-file=${cfg.joinTokenFile}"]
    ++ cfg.agentExtraFlags;
  serverFlags = cfg.serverExtraFlags;
  interfaceWaitScript = ''
    attempt=0
    while [ "$attempt" -lt ${toString cfg.waitForInterface.timeoutSeconds} ]; do
      if [ -n "$(${pkgs.iproute2}/bin/ip -o -4 addr show dev ${cfg.waitForInterface.name} scope global 2>/dev/null)" ]; then
        exit 0
      fi
      attempt=$((attempt + 1))
      ${pkgs.coreutils}/bin/sleep 1
    done

    echo "${cfg.waitForInterface.name} did not receive a global IPv4 address within ${toString cfg.waitForInterface.timeoutSeconds}s" >&2
    exit 1
  '';
in {
  options.platformBlueprints.k3s = {
    enable = lib.mkEnableOption "generic k3s host behavior";

    role = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "server"
        "agent"
      ]);
      default = null;
      description = "Optional k3s role managed by this blueprint.";
    };

    apiServerEndpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "k3s API server endpoint used by agent nodes.";
    };

    joinTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime path of the k3s agent join token.";
    };

    nodeLabels = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Kubernetes node labels emitted as k3s flags.";
    };

    nodeTaints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Kubernetes node taints emitted as k3s flags.";
    };

    flannelInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional interface name passed to k3s as --flannel-iface.";
    };

    waitForInterface = {
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional interface that must have a global IPv4 address before k3s starts.";
      };

      timeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 60;
        description = "Seconds to wait for waitForInterface.name.";
      };
    };

    requiredServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Systemd services k3s pulls in and starts after (Wants=, not Requires=, so restarting one never stops k3s).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open common k3s firewall ports.";
    };

    serverExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional flags for server nodes.";
    };

    agentExtraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional flags for agent nodes.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = lib.optionals isAgent [
        {
          assertion = cfg.apiServerEndpoint != null && cfg.apiServerEndpoint != "";
          message = "k3s agent nodes require platformBlueprints.k3s.apiServerEndpoint";
        }
        {
          assertion = cfg.joinTokenFile != null && cfg.joinTokenFile != "";
          message = "k3s agent nodes require platformBlueprints.k3s.joinTokenFile";
        }
      ];

      services.k3s = {
        enable = true;
        extraFlags = lib.mkAfter (
          flannelFlags
          ++ labelFlags
          ++ taintFlags
          ++ lib.optionals isServer serverFlags
          ++ lib.optionals isAgent agentFlags
        );
      };
    }

    (lib.mkIf (cfg.role != null) {
      services.k3s.role = cfg.role;
    })

    (lib.mkIf (isAgent && cfg.apiServerEndpoint != null) {
      services.k3s.serverAddr = lib.mkDefault cfg.apiServerEndpoint;
    })

    (lib.mkIf (cfg.openFirewall) {
      networking.firewall.allowedTCPPorts =
        [10250]
        ++ lib.optionals isServer [6443];
      networking.firewall.allowedUDPPorts = [8472];
    })

    (lib.mkIf (tokenDirectory != null) {
      systemd.tmpfiles.rules = [
        "d ${tokenDirectory} 0700 root root - -"
      ];
    })

    (lib.mkIf (cfg.requiredServices != []) {
      systemd.services.k3s = {
        after = cfg.requiredServices;
        wants = cfg.requiredServices;
      };
    })

    (lib.mkIf (cfg.waitForInterface.name != null) {
      systemd.services.k3s.preStart = lib.mkBefore interfaceWaitScript;
    })
  ]);
}
