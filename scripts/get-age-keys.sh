#!/usr/bin/env bash
set -euo pipefail

declare -A hosts=(
  [zeus]=192.168.1.10
  [gaea]=192.168.1.11
  [pik8s1]=192.168.1.101
  [pik8s2]=192.168.1.102
  [pik8s3]=192.168.1.103
  [pik8s4]=10.0.69.104
  [pik8s5]=10.0.69.105
  [pik8s6]=10.0.69.106
)

for host in "${!hosts[@]}"; do
  ip="${hosts[$host]}"
  if key=$(ssh-keyscan -t ed25519 "$ip" 2>/dev/null | ssh-to-age); then
    echo "&${host} ${key}"
  else
    echo "WARN: failed to get key for ${host} (${ip})" >&2
  fi
done
