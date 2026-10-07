#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -Eeuo pipefail
readonly URL="https://raw.githubusercontent.com/0157Martin/cloudflare-ip-manager/main/cloudflare-ip-manager.sh"
readonly BIN="/usr/local/bin/cloudflare-ip-manager"
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo '请使用 root 运行。' >&2; exit 1; }
case "${1:-install}" in
  install)
    command -v curl >/dev/null || { echo '缺少 curl。' >&2; exit 1; }
    temporary=$(mktemp); trap 'rm -f "$temporary"' EXIT
    curl -fL --retry 3 --connect-timeout 10 "$URL" -o "$temporary"
    bash -n "$temporary"
    grep -q 'SPDX-License-Identifier: GPL-3.0-or-later' "$temporary"
    install -m 755 "$temporary" "$BIN"
    "$BIN" install
    ;;
  verify) [[ -x $BIN ]] || { echo '未安装。' >&2; exit 1; }; "$BIN" version; "$BIN" help >/dev/null; [[ ! -e /etc/cloudflare-ip-manager/selected.env ]] || "$BIN" verify ;;
  uninstall) [[ -x $BIN ]] && "$BIN" uninstall || rm -rf /etc/cloudflare-ip-manager ;;
  *) echo '用法：install.sh [install|verify|uninstall]' >&2; exit 1 ;;
esac
