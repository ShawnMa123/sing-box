# Sing-Box Docker 部署指南

基于官方 install.sh 脚本功能的 Docker 容器化解决方案，支持通过环境变量配置所有协议和选项。

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone <repository-url>
cd sing-box
```

### 2. 准备环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置
vim .env
```

### 3. 选择协议并启动

```bash
# 启动 VLESS Reality (推荐)
docker-compose --profile vless-reality up -d

# 启动 Trojan
docker-compose --profile trojan up -d

# 启动 Shadowsocks
docker-compose --profile shadowsocks up -d

# 启动多个协议
docker-compose --profile vless-reality --profile shadowsocks up -d
```

## 📋 支持的协议

| 协议 | Profile | 端口 | 说明 |
|------|---------|------|------|
| VLESS Reality | `vless-reality` | 443 | 推荐，最新抗审查技术 |
| Trojan | `trojan` | 8443 | 经典伪装协议 |
| VMess WebSocket | `vmess-ws` | 8080 | 兼容性好 |
| Shadowsocks | `shadowsocks` | 8388 | 轻量级代理 |
| Hysteria2 | `hysteria2` | 36712 | 基于QUIC的高速协议 |
| TUIC | `tuic` | 8443 | QUIC代理协议 |
| Socks5 | `socks5` | 1080 | 标准代理协议 |

## 🔧 环境变量配置

### 基础配置

```bash
# 协议类型
PROTOCOL=vless-reality

# 服务端口
PORT=443

# UUID (留空自动生成)
UUID=550e8400-e29b-41d4-a716-446655440000

# 日志级别
LOG_LEVEL=info
```

### Reality 配置

```bash
# 伪装域名 (推荐大型网站)
SERVER_NAME=www.cloudflare.com

# 密钥对 (留空自动生成)
PRIVATE_KEY=
PUBLIC_KEY=

# 流控类型
FLOW=xtls-rprx-vision
```

### 传输层配置

```bash
# 传输协议
TRANSPORT=tcp

# WebSocket 路径
WS_PATH=/vmess-ws

# Host 头
HOST_HEADER=example.com
```

## 📖 使用示例

### VLESS Reality (推荐)

最新的抗审查技术，无需证书即可实现TLS伪装：

```bash
# .env 配置
PROTOCOL=vless-reality
PORT=443
UUID=your-uuid-here
SERVER_NAME=www.cloudflare.com

# 启动
docker-compose --profile vless-reality up -d

# 查看生成的密钥
docker logs singbox-vless-reality
```

### Shadowsocks 2022

现代化的 Shadowsocks 实现：

```bash
# .env 配置
PROTOCOL=shadowsocks
PORT=8388
SS_METHOD=2022-blake3-aes-256-gcm

# 启动
docker-compose --profile shadowsocks up -d
```

### Trojan

经典的TLS伪装协议：

```bash
# .env 配置
PROTOCOL=trojan
PORT=8443
TROJAN_PASSWORD=your-strong-password

# 启动
docker-compose --profile trojan up -d
```

## 🎛️ 高级配置

### 自定义配置文件

如果需要更复杂的配置，可以直接提供配置文件：

```bash
# 创建配置目录
mkdir -p ./config

# 编写自定义配置
cat > ./config/custom-config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 443,
      "users": [{"uuid": "your-uuid"}],
      "tls": {
        "enabled": true,
        "server_name": "www.example.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.example.com",
            "server_port": 443
          },
          "private_key": "your-private-key"
        }
      }
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"}
  ]
}
EOF

# 使用自定义配置启动
docker run -d \
  --name singbox-custom \
  -p 443:443 \
  -v ./config/custom-config.json:/etc/sing-box/config.json:ro \
  -v ./data/logs:/var/log/sing-box \
  sing-box:latest
```

### 多端口多协议

```yaml
# docker-compose.override.yml
version: '3.8'
services:
  multi-protocol:
    build: .
    ports:
      - "443:443"    # VLESS Reality
      - "8080:8080"  # VMess WS
      - "8388:8388"  # Shadowsocks
    volumes:
      - ./config/multi-protocol.json:/etc/sing-box/config.json:ro
```

## 🔍 监控和维护

### 查看日志

```bash
# 查看实时日志
docker-compose logs -f vless-reality

# 查看配置生成日志
docker logs singbox-vless-reality

# 查看详细日志文件
tail -f ./data/vless-reality/logs/access.log
```

### 健康检查

```bash
# 检查容器状态
docker-compose ps

# 检查配置文件
docker exec singbox-vless-reality /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json

# 查看生成的配置
docker exec singbox-vless-reality cat /etc/sing-box/config.json
```

### 重启服务

```bash
# 重启单个服务
docker-compose restart vless-reality

# 重新生成配置并重启
docker-compose down vless-reality
docker-compose --profile vless-reality up -d
```

## 🛡️ 安全建议

1. **更改默认端口**: 避免使用常见端口
2. **强密码**: 为 Trojan/Socks 使用强密码
3. **定期更新**: 定期更新 sing-box 版本
4. **防火墙**: 配置适当的防火墙规则
5. **监控**: 监控异常流量和连接

```bash
# 更新到最新版本
docker-compose pull
docker-compose --profile vless-reality up -d
```

## 🐛 故障排除

### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口占用
   ss -tulpn | grep :443

   # 修改端口
   PORT=8443 docker-compose --profile vless-reality up -d
   ```

2. **配置文件错误**
   ```bash
   # 验证配置
   docker exec singbox-vless-reality /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json

   # 查看错误日志
   docker logs singbox-vless-reality
   ```

3. **Reality 密钥问题**
   ```bash
   # 重新生成密钥
   docker exec singbox-vless-reality /opt/sing-box/bin/sing-box generate reality-keypair
   ```

### 获取客户端配置

```bash
# 查看完整的连接信息
docker logs singbox-vless-reality 2>&1 | grep -E "(UUID|公钥|端口)"

# 导出配置文件
docker exec singbox-vless-reality cat /etc/sing-box/config.json > client-config.json
```

## 📚 参考资料

- [Sing-Box 官方文档](https://sing-box.sagernet.org/)
- [Reality 协议说明](https://github.com/XTLS/REALITY)
- [Docker Compose 文档](https://docs.docker.com/compose/)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 📄 许可证

本项目基于原始 install.sh 脚本，遵循相同的开源许可证。