{
  clan = {
    meta = {
      name = "thecluster";
      domain = "thecluster.io";
      description = "THECLUSTER";
    };

    inventory.machines = {
      pik8s1 = {
        deploy.targetHost = "root@192.168.1.101";
        tags = [
          "pi"
          "k8s"
          "control-plane"
        ];
      };
    };

    machines = { };
  };
}
