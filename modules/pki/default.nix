# ca.pem copies UnstoppableMango/pki's certs/ca.pem, valid until 2051.
# thecluster-lan-nginx-ca.pem is the pre-ceremony CA the-cluster's gateway
# still serves; drop it once the gateway serves the new chain.
# Chromium ignores the system bundle, so ../brave hands it ca.pem by policy.
{
  security.pki.certificateFiles = [
    ./ca.pem
    ./thecluster-lan-nginx-ca.pem
  ];
}
