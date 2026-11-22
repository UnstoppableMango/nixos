# The bearer token for every Gatus external endpoint. Shared, because Gatus
# and every machine pushing to it need the same value.
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
}
