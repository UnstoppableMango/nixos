# Trusts the UnMango Root CA G2 from UnstoppableMango/pki, which every
# *.thecluster.lan certificate chains to through UnMango Private CA 01.
# ca.pem is a copy of that repo's certs/ca.pem; the root is valid until 2051,
# and only a new root ceremony changes it.
#
# thecluster-lan-nginx-ca.pem is the pre-ceremony CA (thecluster.io, under
# UnMango Authority), which the-cluster's gateway still serves. It is kept
# until the gateway serves the new chain, and lives here so every machine
# trusts it rather than only the ones that carried a copy.
#
# security.pki covers the system bundle, which curl, Go, nix, and Firefox
# through p11-kit read. Chromium-based browsers on Linux ignore it, so
# ../brave hands them ca.pem through policy.
{
  security.pki.certificateFiles = [
    ./ca.pem
    ./thecluster-lan-nginx-ca.pem
  ];
}
