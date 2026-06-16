{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cluster.rosequartz;

  clientExt = ''
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=clientAuth'';

  serverExt = sans: ''
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=serverAuth
    subjectAltName=${sans}'';

  peerExt = sans: ''
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=serverAuth,clientAuth
    subjectAltName=${sans}'';

  # Returns a complete bash script that signs one cert using the rosequartz-ca dependency.
  # subj and ext are Nix strings interpolated at eval time; $in comes from the clan dep env.
  sign = subj: ext: ''
    set -euo pipefail
    openssl req -newkey rsa:${toString cfg.pki.keyBits} -nodes \
      -keyout "$out/key" -subj "${subj}" -out tmp.csr 2>/dev/null
    openssl x509 -req -in tmp.csr \
      -CA "$in/rosequartz-ca/crt" -CAkey "$in/rosequartz-ca/key" -CAcreateserial \
      -days ${toString cfg.pki.certValidityDays} -sha256 \
      -extfile <(printf '%s' "${ext}") \
      -out "$out/crt" 2>/dev/null
  '';

  mkCert = share: subj: ext: owner: {
    inherit share;
    runtimeInputs = [ pkgs.openssl ];
    dependencies = [ "rosequartz-ca" ];
    files."crt".secret = false;
    files."key" = { secret = true; inherit owner; };
    script = sign subj ext;
  };

in
{
  options.cluster.rosequartz.pki = {
    keyBits = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "RSA key size in bits for all generated certificates.";
    };

    certValidityDays = lib.mkOption {
      type = lib.types.int;
      default = 3650;
      description = "Validity period in days for all generated certificates.";
    };

    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      internal = true;
      description = "Certificate signing helpers derived from pki options; access via inherit.";
      default = {
        inherit clientExt serverExt peerExt sign mkCert;
        mkSharedCert = mkCert true;
        mkNodeCert = mkCert false;
      };
    };
  };

  config = {
    clan.core.vars.generators = {
      "rosequartz-ca" = {
        share = true;
        prompts."ca-crt" = {
          description = "Cluster CA certificate (PEM)";
          type = "multiline";
        };
        prompts."ca-key" = {
          description = "Cluster CA private key (PEM)";
          type = "multiline-hidden";
        };
        files."crt".secret = false;
        files."key" = {
          secret = true;
          deploy = false;
        };
        script = ''
          set -euo pipefail
          cp "$prompts/ca-crt" "$out/crt"
          cp "$prompts/ca-key" "$out/key"
        '';
      };
    };
  };
}
