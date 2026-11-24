# Chromium's `CACertificates` policy: Chromium on Linux ignores the system
# bundle ../pki fills. Shared with the brave-certificates-policy package.
let
  pem = builtins.readFile ../pki/ca.pem;
  lines = builtins.filter (l: builtins.isString l && l != "" && builtins.substring 0 5 l != "-----") (
    builtins.split "\n" pem
  );
in
{
  CACertificates = [ (builtins.concatStringsSep "" lines) ];
}
