{
  config,
  pkgs,
  ...
}:
let
  cfg = config.cluster.rosequartz;
  kubeconfigPath = "/etc/kubernetes/admin.kubeconfig";
in
{
  config = {
    cluster.rosequartz.pki.certs.admin-cert = {
      cn = "kubernetes-admin";
      org = "system:masters";
      profile = "client";
      owner = "root";
    };

    environment.etc."kubernetes/admin.kubeconfig" = {
      mode = "0600";
      text = ''
        apiVersion: v1
        kind: Config
        clusters:
        - cluster:
            certificate-authority: ${cfg.pki.ca.cert}
            server: https://${cfg.vip}:6443
          name: ${cfg.clusterName}
        contexts:
        - context:
            cluster: ${cfg.clusterName}
            user: kubernetes-admin
          name: ${cfg.clusterName}
        current-context: ${cfg.clusterName}
        users:
        - name: kubernetes-admin
          user:
            client-certificate: ${cfg.pki.certs."admin-cert".cert}
            client-key: ${cfg.pki.certs."admin-cert".key}
      '';
    };

    environment.systemPackages = [ pkgs.kubectl ];

    environment.variables.KUBECONFIG = kubeconfigPath;
  };
}
