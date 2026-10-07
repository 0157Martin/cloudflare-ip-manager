# cloudflare-ip-manager

Cloudflare 优选入口 IP 的独立测试和状态项目，由 **0157Martin** 维护。它不修改 DNS、Caddy 或 Xray；`v2ray-manager` 只调用它，并在导出 TLS XHTTP/WebSocket 链接时把保存的 IP 用作连接地址。TLS 的 SNI 和 HTTP Host 始终保留原域名。

## 安装、验证与卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0157Martin/cloudflare-ip-manager/main/install.sh)
cloudflare-ip-manager set 1.1.1.1 edge.example.com
cloudflare-ip-manager verify
cloudflare-ip-manager show
bash <(curl -fsSL https://raw.githubusercontent.com/0157Martin/cloudflare-ip-manager/main/install.sh) uninstall
```

`1.1.1.1` 只是命令格式示例，请替换成属于 Cloudflare 边缘网络且能为你的域名完成 TLS 的候选地址。

批量测试由用户明确提供的候选地址：

```bash
cloudflare-ip-manager test edge.example.com 'IP1,IP2,IP3'
```

项目以 HTTPS 状态和 TTFB 筛选候选，不内置容易过期的 IP 列表，也不会宣称服务器测试结果等同于客户端网络。最终应从实际使用网络复测。

主干读取方式：

```bash
v2ray cfip show
v2ray link <入站ID> cfip
```

只有 TLS XHTTP/WebSocket 入站支持这种导出形式。

## 状态边界

- 命令：`/usr/local/bin/cloudflare-ip-manager`
- 状态：`/etc/cloudflare-ip-manager/selected.env`（权限 `600`）
- 卸载只删除本项目命令和状态
- 不保存证书、UUID、DNS API Token 或 Cloudflare 账户凭据

许可证：GPL-3.0-or-later。
