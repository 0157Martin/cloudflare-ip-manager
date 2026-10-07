#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export CFIP_STATE_DIR="$tmp/state"
# shellcheck disable=SC1091
source "$root/cloudflare-ip-manager.sh"
valid_public_ipv4 104.16.1.1
valid_public_ipv4 127.0.0.1 && exit 1
valid_public_ipv4 192.168.1.1 && exit 1
valid_public_ipv4 999.1.1.1 && exit 1
valid_domain edge.example.com
valid_domain localhost && exit 1
save_selection 104.16.1.1 edge.example.com test
[[ $(main get) == 104.16.1.1 ]]
[[ $(stat -c '%a' "$STATE_FILE") == 600 ]]
printf 'unit tests passed\n'
