# The host and the VM share a /30 on the VM's tap, outside every LAN and
# cluster range in NETWORK.md.
{
  tap = "vm-builder";
  mac = "02:00:0a:00:47:06";
  host = "10.0.71.5";
  guest = "10.0.71.6";
  prefixLength = 30;
  cid = 4;
}
