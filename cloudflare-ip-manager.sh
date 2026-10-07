#!/usr/bin/env bash
# Cloudflare preferred IP tester and state manager.
# Author: 0157Martin (https://github.com/0157Martin)
# SPDX-License-Identifier: GPL-3.0-or-later
set -Eeuo pipefail

readonly VERSION="1.0.0"
readonly STATE_DIR="${CFIP_STATE_DIR:-/etc/cloudflare-ip-manager}"
readonly STATE_FILE="$STATE_DIR/selected.env"

die() { printf '\033[31m错误：%s\033[0m\n' "$*" >&2; exit 1; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

valid_domain() {
  [[ ${1:-} =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && $1 == *.* && $1 != *..* ]]
}

valid_public_ipv4() {
  local ip=${1:-} octet
  local -a octets
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a octets <<<"$ip"
  for octet in "${octets[@]}"; do ((10#$octet <= 255)) || return 1; done
  case "$ip" in
    0.*|10.*|127.*|169.254.*|192.0.0.*|192.0.2.*|192.168.*|198.18.*|198.19.*|198.51.100.*|203.0.113.*|224.*|225.*|226.*|227.*|228.*|229.*|230.*|231.*|232.*|233.*|234.*|235.*|236.*|237.*|238.*|239.*|24[0-9].*|25[0-5].*) return 1 ;;
  esac
  [[ ${octets[0]} -ne 172 || ${octets[1]} -lt 16 || ${octets[1]} -gt 31 ]]
}

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die '请使用 root 运行。'; }

save_selection() {
  local ip=$1 domain=$2 source=${3:-manual}
  valid_public_ipv4 "$ip" || die "不是可用的公网 IPv4：$ip"
  valid_domain "$domain" || die "Cloudflare TLS 域名无效：$domain"
  install -d -m 700 "$STATE_DIR"
  umask 077
  {
    printf 'CFIP_ADDRESS=%q\n' "$ip"
    printf 'CFIP_DOMAIN=%q\n' "${domain,,}"
    printf 'CFIP_SOURCE=%q\n' "$source"
    printf 'CFIP_UPDATED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$STATE_FILE.tmp"
  mv -f "$STATE_FILE.tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

load_selection() {
  [[ -r $STATE_FILE ]] || die '尚未保存优选 IP。先运行 test 或 set。'
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  valid_public_ipv4 "${CFIP_ADDRESS:-}" || die '状态文件中的 IP 无效。'
  valid_domain "${CFIP_DOMAIN:-}" || die '状态文件中的域名无效。'
}

probe() {
  local domain=$1 ip=$2 output
  output=$(curl -4fsS -o /dev/null --connect-timeout 4 --max-time 10 \
    --resolve "$domain:443:$ip" -w '%{http_code} %{time_connect} %{time_starttransfer}' \
    "https://$domain/cdn-cgi/trace" 2>/dev/null) || return 1
  [[ ${output%% *} =~ ^[234][0-9][0-9]$ ]] || return 1
  printf '%s\n' "$output"
}

test_candidates() {
  local domain=${1:-} input=${2:-} item ip result http connect ttfb best_ip='' best_ttfb='999999'
  valid_domain "$domain" || die '用法：cloudflare-ip-manager test <Cloudflare域名> <IP,IP,...>'
  [[ -n $input ]] || die '候选 IP 不能为空；本项目不内置可能过期的地址列表。'
  input=${input//,/ }
  printf 'IP                 HTTP   connect(s)  TTFB(s)\n'
  printf '%s\n' '------------------------------------------------'
  for item in $input; do
    ip=${item//$'\r'/}
    if ! valid_public_ipv4 "$ip"; then printf '%-18s %s\n' "$ip" '跳过：不是公网 IPv4'; continue; fi
    if result=$(probe "$domain" "$ip"); then
      read -r http connect ttfb <<<"$result"
      printf '%-18s %-6s %-11s %s\n' "$ip" "$http" "$connect" "$ttfb"
      if awk -v a="$ttfb" -v b="$best_ttfb" 'BEGIN {exit !(a < b)}'; then best_ip=$ip; best_ttfb=$ttfb; fi
    else
      printf '%-18s %s\n' "$ip" '失败'
    fi
  done
  [[ -n $best_ip ]] || die '没有候选 IP 通过 HTTPS/SNI 验证。'
  save_selection "$best_ip" "$domain" tested
  green "已保存：$best_ip（域名 $domain，TTFB ${best_ttfb}s）"
  yellow '服务器侧结果只反映当前 VPS 到 Cloudflare；请在实际客户端网络复测延迟和可用性。'
}

show_selection() {
  load_selection
  printf '优选 IP：%s\nTLS/SNI/Host 域名：%s\n来源：%s\n更新时间：%s\n' \
    "$CFIP_ADDRESS" "$CFIP_DOMAIN" "${CFIP_SOURCE:-unknown}" "${CFIP_UPDATED_AT:-unknown}"
}

verify_selection() {
  local result
  load_selection
  result=$(probe "$CFIP_DOMAIN" "$CFIP_ADDRESS") || die '已保存组合未通过 HTTPS/SNI 验证。'
  green "验证通过：$CFIP_ADDRESS -> $CFIP_DOMAIN（HTTP ${result%% *}）"
}

usage() {
  cat <<'EOF'
cloudflare-ip-manager 1.0.0 by 0157Martin
  install                         检查依赖并初始化
  test <域名> <IP,IP,...>         测试候选并保存最低 TTFB 地址
  set <IP> <域名>                 手动保存入口 IP 和 TLS 域名
  verify                          验证已保存组合
  show                            显示已保存组合
  get                             仅输出已保存 IP，供主干调用
  domain                          仅输出已保存 TLS 域名，供主干校验
  clear                           清除选择
  uninstall                       删除命令和状态
EOF
}

main() {
  local command=${1:-help}
  case "$command" in
    install) require_root; command -v curl >/dev/null || die '缺少 curl。'; install -d -m 700 "$STATE_DIR"; green 'cloudflare-ip-manager 已就绪。' ;;
    test) require_root; command -v curl >/dev/null || die '缺少 curl。'; test_candidates "${2:-}" "${3:-}" ;;
    set) require_root; save_selection "${2:-}" "${3:-}" manual; green '已保存优选入口。' ;;
    verify) command -v curl >/dev/null || die '缺少 curl。'; verify_selection ;;
    show|status) show_selection ;;
    get) load_selection; printf '%s\n' "$CFIP_ADDRESS" ;;
    domain) load_selection; printf '%s\n' "$CFIP_DOMAIN" ;;
    clear) require_root; rm -f -- "$STATE_FILE"; green '已清除优选 IP。' ;;
    uninstall) require_root; rm -rf -- "$STATE_DIR"; rm -f -- /usr/local/bin/cloudflare-ip-manager; green '已卸载 cloudflare-ip-manager。' ;;
    version|-v|--version) printf 'cloudflare-ip-manager %s by 0157Martin\n' "$VERSION" ;;
    help|-h|--help) usage ;;
    *) die "未知命令：$command" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
