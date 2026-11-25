# What the host does for each microVM on it: a tap with a routed /30 from
# NETWORK.md, the VM's logical volume in the `vms` group, a read-only secrets
# disk, and a filter on what the VM may reach.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vmHost;
  ip = lib.getExe' pkgs.iproute2 "ip";
  gatus = builtins.match "https://([0-9.]+):([0-9]+)" (toString config.diskPush.url);

  vm =
    { name, ... }:
    {
      options = with lib.types; {
        tap = lib.mkOption { type = str; };
        host = lib.mkOption { type = str; };
        prefixLength = lib.mkOption { type = int; };
        secrets = lib.mkOption {
          type = attrsOf str;
          default = { };
          description = "Files on the host, by the name the VM reads them under.";
        };
        secretsImage = lib.mkOption {
          type = str;
          readOnly = true;
          default = "/run/microvm-${name}/secrets.erofs";
        };
        filter = lib.mkOption {
          type = listOf str;
          description = "iptables rules, without `-A <chain>`, for packets the VM opens a connection with. `RETURN` lets one through.";
        };
      };
    };
in
{
  options.vmHost = {
    interface = lib.mkOption {
      type = lib.types.str;
      example = "eno1";
      description = "LAN interface the VMs are reached on and NATed out of.";
    };
    lanAddress = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = (lib.head config.networking.interfaces.${cfg.interface}.ipv4.addresses).address;
    };
    gatus = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = {
        ip = lib.elemAt gatus 0;
        port = lib.elemAt gatus 1;
      };
      description = "Address and port of `diskPush.url`, for VM filters that let pushes through.";
    };
    vms = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule vm);
      default = { };
    };
  };

  config = lib.mkIf (cfg.vms != { }) {
    assertions = [
      {
        assertion = gatus != null;
        message = "modules/vm-host: diskPush.url must be https://<ip>:<port>, which the VM filters read.";
      }
    ];

    # No VM here runs a hypervisor of its own.
    boot.extraModprobeConfig = "options kvm_amd nested=0";

    networking.nat = {
      enable = true;
      externalInterface = cfg.interface;
      externalIP = cfg.lanAddress;
    };

    services.udev.extraRules = lib.concatMapStrings (name: ''
      ENV{DM_VG_NAME}=="vms", ENV{DM_LV_NAME}=="${name}", OWNER="microvm", GROUP="kvm", MODE="0600"
    '') (lib.attrNames cfg.vms);

    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: vm: {
        "microvm@${name}" = {
          requires = [ "dev-vms-${name}.device" ];
          after = [ "dev-vms-${name}.device" ];
        };

        # The tap only exists while the VM runs, so it gets its address here.
        "microvm-tap-interfaces@${name}".serviceConfig.ExecStartPost = [
          "${ip} address add ${vm.host}/${toString vm.prefixLength} dev ${vm.tap}"
          "${lib.getExe' pkgs.procps "sysctl"} -w net.ipv6.conf.${vm.tap}.disable_ipv6=1"
        ];

        # cloud-hypervisor takes no credentials, so the secrets reach the VM as
        # a read-only disk.
        "microvm-${name}-secrets" = lib.mkIf (vm.secrets != { }) {
          description = "Build the ${name} MicroVM's secrets disk";
          before = [ "microvm@${name}.service" ];
          requiredBy = [ "microvm@${name}.service" ];
          partOf = [ "microvm@${name}.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "microvm-${name}";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";
            LoadCredential = lib.mapAttrsToList (file: path: "${file}:${path}") vm.secrets;
          };
          script = ''
            ${lib.getExe' pkgs.erofs-utils "mkfs.erofs"} --quiet ${vm.secretsImage} "$CREDENTIALS_DIRECTORY"
            chown -R microvm:kvm "$RUNTIME_DIRECTORY"
          '';
        };
      }) cfg.vms
    );

    # mangle runs before kube-proxy's DNAT and flannel's FORWARD accepts.
    # A reload runs the stop commands first, so nothing removes the filter.
    # Rules alternate between two chains, and the live one is only removed
    # once the other takes traffic, wherever an earlier run stopped.
    networking.firewall.extraCommands = lib.concatStrings (
      lib.mapAttrsToList (name: vm: ''
        mangle="iptables -w -t mangle"
        jump="PREROUTING -i ${vm.tap} -j"
        if $mangle -C $jump ${name}-vm-a 2>/dev/null; then
          live=${name}-vm-a next=${name}-vm-b
        else
          live=${name}-vm-b next=${name}-vm-a
        fi
        while $mangle -D $jump $next 2>/dev/null; do :; done
        $mangle -F $next 2>/dev/null || $mangle -N $next
        $mangle -A $next -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
        ${lib.concatMapStringsSep "\n" (rule: "$mangle -A $next ${rule}") vm.filter}
        $mangle -I $jump $next
        while $mangle -D $jump $live 2>/dev/null; do :; done
        $mangle -F $live 2>/dev/null || true
        $mangle -X $live 2>/dev/null || true
      '') cfg.vms
    );
  };
}
