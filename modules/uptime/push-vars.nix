# Vars Gatus and every machine pushing to it both read. Shared, so each side
# sees the same values.
{ pkgs, ... }:
{
  clan.core.vars.generators.uptime-push = {
    share = true;
    files.token.secret = true;
    files.env.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 | tr -d '\n' > "$out/token"
      printf 'GATUS_PUSH_TOKEN=%s\n' "$(cat "$out/token")" > "$out/env"
    '';
  };

  # Pushers pin `pubkey` rather than verify a name, so the cert needs no SAN
  # for whatever address they dial.
  clan.core.vars.generators.uptime-tls = {
    share = true;
    files.key.deploy = false;
    files.cert.secret = false;
    files.pubkey.secret = false;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -days 36500 -subj /CN=gatus \
        -keyout "$out/key" -out "$out/cert"
      openssl pkey -in "$out/key" -pubout -out "$out/pubkey"
    '';
  };
}
