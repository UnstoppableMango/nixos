# Chromium's `CACertificates` policy: base64 DER certificates trusted for
# server authentication. Chromium on Linux reads trust anchors from its own
# NSS database rather than the system bundle that ../pki fills, so the
# UnMango Root CA G2 has to reach it this way. Shared with the
# brave-certificates-policy package, which is how darter gets the same file.
let
  pem = builtins.readFile ../pki/ca.pem;
  lines = builtins.filter (l: builtins.isString l && l != "" && builtins.substring 0 5 l != "-----") (
    builtins.split "\n" pem
  );
in
{
  CACertificates = [ (builtins.concatStringsSep "" lines) ];
}
