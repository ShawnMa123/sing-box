# Sing-Box Docker 部署方案

基于原 `install.sh` 脚本的完整 Docker 容器化解决方案。通过环境变量控制所有配置选项，支持多种代理协议。

## 🎯 项目目标

将 `install.sh` 脚本的所有功能转换为 Docker 容器部署，实现：
- ✅ 支持所有主流代理协议 (VLESS, Trojan, VMess, Shadowsocks 等)
- ✅ 通过环境变量灵活配置端口、协议参数
- ✅ 自动生成密钥、UUID、密码
- ✅ 多架构支持 (amd64, arm64)
- ✅ 交互式快速部署脚本

## 📁 项目结构

```
.
├── Dockerfile                    # 多阶段构建文件
├── docker-compose.yml           # 多协议服务编排
├── .env.example                 # 环境变量模板
├── docker/
│   ├── entrypoint.sh            # 容器入口脚本
│   ├── config-generator.sh      # 配置生成器
│   ├── build.sh                 # 构建脚本
│   ├── quick-start.sh           # 快速启动脚本
│   └── README.md                # 详细使用说明
└── DOCKER-DEPLOYMENT.md         # 本文档
```

## 🚀 快速开始

### 方法一：交互式部署 (推荐)

```bash
# 使用快速启动脚本
./docker/quick-start.sh
```

该脚本提供完全交互式的配置体验：
- 选择代理协议
- 配置端口和参数
- 自动生成 .env 文件
- 一键启动服务

### 方法二：预配置部署

```bash
# 1. 复制环境变量模板
cp .env.example .env

# 2. 编辑配置
vim .env

# 3. 启动指定协议
docker-compose --profile vless-reality up -d
```

### 方法三：直接运行

```bash
# VLESS Reality (推荐)
docker run -d \
  --name singbox \
  -p 443:443 \
  -e PROTOCOL=vless-reality \
  -e PORT=443 \
  -e UUID=$(uuidgen) \
  -e SERVER_NAME=www.cloudflare.com \
  sing-box:latest
```

## 🛠️ 支持的协议配置

### VLESS Reality (推荐)
最新的抗审查技术，无需证书即可实现完美TLS伪装：

```bash
PROTOCOL=vless-reality
PORT=443
UUID=your-uuid
SERVER_NAME=www.cloudflare.com
TRANSPORT=tcp
FLOW=xtls-rprx-vision
```

### Trojan
经典的TLS伪装协议：

```bash
PROTOCOL=trojan
PORT=8443
TROJAN_PASSWORD=your-password
TRANSPORT=tcp
```

### VMess WebSocket
高兼容性的WebSocket传输：

```bash
PROTOCOL=vmess-ws-tls
PORT=8080
UUID=your-uuid
TRANSPORT=ws
WS_PATH=/vmess-path
HOST_HEADER=example.com
```

### Shadowsocks 2022
现代化Shadowsocks实现：

```bash
PROTOCOL=shadowsocks
PORT=8388
SS_METHOD=2022-blake3-aes-256-gcm
SS_PASSWORD=auto-generated
```

### Hysteria2
基于QUIC的高速协议：

```bash
PROTOCOL=hysteria2
PORT=36712
TROJAN_PASSWORD=your-password
```

### TUIC
QUIC代理协议：

```bash
PROTOCOL=tuic
PORT=8443
UUID=your-uuid
TROJAN_PASSWORD=your-password
```

### Socks5
标准代理协议：

```bash
PROTOCOL=socks
PORT=1080
SOCKS_USER=username
SOCKS_PASS=password
```

## 🔧 高级功能

### 1. 多架构构建

```bash
# 构建多架构镜像
./docker/build.sh --platforms linux/amd64,linux/arm64

# 构建特定版本
./docker/build.sh --version v1.8.0 --tag v1.8.0
```

### 2. 自定义配置文件

```bash
# 使用外部配置文件
docker run -d \
  --name singbox-custom \
  -p 443:443 \
  -v ./config.json:/etc/sing-box/config.json:ro \
  sing-box:latest
```

### 3. 多协议混合部署

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
      - ./config/multi.json:/etc/sing-box/config.json:ro
```

## 📊 环境变量参考

### 基础配置
- `PROTOCOL`: 协议类型 (必填)
- `PORT`: 服务端口 (必填)
- `UUID`: 用户ID (可选，自动生成)
- `LOG_LEVEL`: 日志级别 (默认: info)

### Reality 配置
- `SERVER_NAME`: 伪装域名
- `PRIVATE_KEY`: 私钥 (自动生成)
- `PUBLIC_KEY`: 公钥 (自动生成)
- `FLOW`: 流控类型

### 传输层配置
- `TRANSPORT`: 传输协议 (tcp/ws/h2/quic)
- `WS_PATH`: WebSocket路径
- `H2_PATH`: HTTP/2路径
- `HOST_HEADER`: Host头

### 协议特定配置
- `TROJAN_PASSWORD`: Trojan密码
- `SS_METHOD`: SS加密方式
- `SS_PASSWORD`: SS密码
- `VMESS_SECURITY`: VMess安全级别
- `SOCKS_USER`: Socks用户名
- `SOCKS_PASS`: Socks密码

## 🔍 监控和维护

### 查看日志
```bash
# 实时日志
docker-compose logs -f vless-reality

# 详细日志文件
tail -f ./data/vless-reality/logs/access.log
```

### 健康检查
```bash
# 检查配置
docker exec singbox-vless-reality \
  /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json

# 查看服务状态
docker-compose ps
```

### 获取连接信息
```bash
# 查看Reality公钥
docker logs singbox-vless-reality 2>&1 | grep "公钥"

# 导出配置
docker exec singbox-vless-reality \
  cat /etc/sing-box/config.json > exported-config.json
```

## 🛡️ 安全建议

1. **更改默认端口**: 避免使用443等常见端口
2. **强密码策略**: 使用脚本自动生成强密码
3. **定期更新**: 保持sing-box版本更新
4. **防火墙配置**: 仅开放必要端口
5. **日志监控**: 监控异常访问模式

## 🚨 故障排除

### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口
   ss -tulpn | grep :443

   # 更改端口
   PORT=8443 docker-compose --profile vless-reality up -d
   ```

2. **配置验证失败**
   ```bash
   # 检查配置语法
   docker run --rm -v ./config.json:/config.json \
     sing-box:latest check -c /config.json
   ```

3. **Reality密钥问题**
   ```bash
   # 重新生成密钥
   docker run --rm sing-box:latest generate reality-keypair
   ```

## 📈 性能优化

### 网络性能
```bash
# 使用host网络模式 (Linux)
docker run -d --network host \
  -e PROTOCOL=vless-reality \
  -e PORT=443 \
  sing-box:latest
```

### 内存优化
```bash
# 限制内存使用
docker run -d --memory=256m \
  sing-box:latest
```

## 🔄 迁移指南

### 从install.sh迁移
1. 备份现有配置: `/etc/sing-box/config.json`
2. 分析配置并转换为环境变量
3. 使用Docker版本部署
4. 验证连通性后停止旧服务

### 配置转换示例
```bash
# 原配置文件分析
jq '.inbounds[0]' /etc/sing-box/config.json

# 转换为环境变量
PROTOCOL=vless-reality
PORT=443
UUID=existing-uuid
SERVER_NAME=existing-servername
```

## 📚 相关资源

- [Sing-Box 官方文档](https://sing-box.sagernet.org/)
- [Reality 协议介绍](https://github.com/XTLS/REALITY)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [多架构构建指南](https://docs.docker.com/build/building/multi-platform/)

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request：

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 发起 Pull Request

## 📄 许可证

本项目基于原 install.sh 脚本，遵循相同的开源协议。

---

🎉 **完美的Docker化部署方案！**

通过环境变量实现了install.sh脚本的所有功能，支持多种协议和灵活配置，提供了完整的容器化部署体验。