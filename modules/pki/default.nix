# Trusts the UnMango Root CA G2 from UnstoppableMango/pki, which every
# *.thecluster.lan certificate chains to through UnMango Private CA 01.
# ca.pem is a copy of that repo's certs/ca.pem; the root is valid until 2051,
# and only a new root ceremony changes it.
#
# security.pki covers the system bundle, which curl, Go, nix, and Firefox
# through p11-kit read. Chromium-based browsers on Linux ignore it, so
# ../brave hands them the same file through policy.
{
  security.pki.certificateFiles = [ ./ca.pem ];
}
