# gaea and the attic VM share a /30 on the VM's tap, outside every LAN and
# cluster range in NETWORK.md.
{
  tap = "vm-attic";
  mac = "02:00:0a:00:47:02";
  host = "10.0.71.1";
  guest = "10.0.71.2";
  prefixLength = 30;
  port = 8080;
  cache = "thecluster";
}
