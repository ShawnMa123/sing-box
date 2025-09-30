# 🚀 Sing-Box 多协议多端口部署指南

完美支持你的使用场景：在单个容器中部署多个协议到不同端口范围，如 Reality 使用端口 1000-1003，Hysteria2 使用端口 2000-2003。

## ⚡ 超级简化的使用方式

### 方法一：一键交互式部署 (最简单)

```bash
# 运行多协议部署脚本
./docker/multi-deploy.sh
```

该脚本提供完全可视化的配置体验：
- 📋 选择预设配置模板或自定义
- 🔧 交互式端口范围配置
- ✅ 自动检测端口冲突
- 🐳 自动生成 Docker 命令
- 🚀 一键启动服务

### 方法二：环境变量快速启动

```bash
# 1. 复制配置模板
cp .env.multi.example .env

# 2. 编辑你的配置 (示例: Reality + Hysteria2)
echo 'MULTI_PROTOCOL_CONFIG="reality:1000-1003:4,hy2:2000-2003:4"' > .env

# 3. 启动服务
docker-compose -f docker-compose.multi.yml up -d singbox-multi
```

### 方法三：直接 Docker 运行

```bash
# 你的经典使用场景
docker run -d \
  --name singbox-multi \
  -p 1000-1003:1000-1003 \
  -p 2000-2003:2000-2003/udp \
  -e MULTI_PROTOCOL_CONFIG="reality:1000-1003:4,hy2:2000-2003:4" \
  -e REALITY_SERVER_NAME="www.cloudflare.com" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest
```

## 📝 配置格式说明

### 基础格式
```
MULTI_PROTOCOL_CONFIG="protocol:port_range:count,protocol:port_range:count"
```

### 支持的协议
- `reality` - VLESS Reality (TCP)
- `hy2` - Hysteria2 (UDP)
- `trojan` - Trojan (TCP)
- `ss` - Shadowsocks (TCP)

### 端口范围格式
- 单端口: `1000`
- 端口范围: `1000-1003`
- 指定端口: `1000,1002,1004,1006`

### 配置示例

```bash
# 你的场景: Reality 4个端口 + Hysteria2 4个端口
MULTI_PROTOCOL_CONFIG="reality:1000-1003:4,hy2:2000-2003:4"

# 全协议测试
MULTI_PROTOCOL_CONFIG="reality:1000-1001:2,hy2:2000-2001:2,trojan:3000-3001:2,ss:4000-4001:2"

# 高密度 Reality
MULTI_PROTOCOL_CONFIG="reality:10000-10019:20"

# 企业级部署
MULTI_PROTOCOL_CONFIG="reality:443-462:20,hy2:8443-8462:20"
```

## 🎯 预定义配置模板

我们提供了多个预设配置，覆盖常见使用场景：

| 模板名称 | 配置内容 | 适用场景 |
|---------|---------|---------|
| 基础双协议 | `reality:1000-1003:4,hy2:2000-2003:4` | 你的经典场景 |
| 全协议测试 | `reality:1000-1001:2,hy2:2000-2001:2,trojan:3000-3001:2,ss:4000-4001:2` | 功能测试 |
| 高密度Reality | `reality:10000-10019:20` | 大量连接 |
| Reality+Hysteria2集群 | `reality:443-462:20,hy2:8443-8462:20` | 生产环境 |

## 🔧 快速启动命令

### 使用预设配置

```bash
# 基础双协议 (你的场景)
docker run -d --name singbox-basic \
  -p 1000-1003:1000-1003 -p 2000-2003:2000-2003/udp \
  -e MULTI_PROTOCOL_CONFIG="reality:1000-1003:4,hy2:2000-2003:4" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest

# 高密度Reality
docker run -d --name singbox-density \
  -p 10000-10019:10000-10019 \
  -e MULTI_PROTOCOL_CONFIG="reality:10000-10019:20" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest
```

### 使用 Docker Compose

```bash
# 启动预定义的基础双协议配置
docker-compose -f docker-compose.multi.yml up -d singbox-multi

# 启动高密度配置
docker-compose -f docker-compose.multi.yml --profile high-density up -d

# 启动全协议配置
docker-compose -f docker-compose.multi.yml --profile all-protocols up -d
```

## 📊 部署后管理

### 查看配置信息

```bash
# 查看生成的配置文件
docker exec singbox-multi cat /etc/sing-box/config.json | jq

# 查看连接信息
docker logs singbox-multi 2>&1 | grep -E "(UUID|公钥|密码)"

# 查看端口分布
docker logs singbox-multi 2>&1 | grep -E "端口|配置完成"
```

### 获取连接参数

```bash
# Reality 公钥
docker logs singbox-multi 2>&1 | grep "Reality 公钥"

# Hysteria2 密码
docker logs singbox-multi 2>&1 | grep "HY2_PORT_.*_PASSWORD"

# 端口列表
docker exec singbox-multi jq -r '.inbounds[] | "\(.type): \(.listen_port)"' /etc/sing-box/config.json
```

### 服务管理

```bash
# 重启服务
docker restart singbox-multi

# 查看日志
docker logs -f singbox-multi

# 查看端口占用
docker port singbox-multi

# 进入容器
docker exec -it singbox-multi /bin/bash
```

## 🔍 故障排除

### 常见问题

1. **端口冲突**
   ```bash
   # 检查端口占用
   ss -tulpn | grep -E ":(1000|2000)"

   # 修改端口范围
   MULTI_PROTOCOL_CONFIG="reality:1100-1103:4,hy2:2100-2103:4"
   ```

2. **配置格式错误**
   ```bash
   # 验证配置格式
   echo "reality:1000-1003:4,hy2:2000-2003:4" | grep -E "^[a-zA-Z0-9_-]+:[0-9]+-?[0-9]*:[0-9]+(,[a-zA-Z0-9_-]+:[0-9]+-?[0-9]*:[0-9]+)*$"
   ```

3. **容器启动失败**
   ```bash
   # 查看详细错误
   docker logs singbox-multi

   # 检查配置文件
   docker exec singbox-multi /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json
   ```

### 性能优化

```bash
# 使用 host 网络模式 (Linux)
docker run -d --network host \
  -e MULTI_PROTOCOL_CONFIG="reality:1000-1003:4,hy2:2000-2003:4" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest

# 限制资源使用
docker run -d --memory=512m --cpus=1.0 \
  -e MULTI_PROTOCOL_CONFIG="reality:1000-1003:4,hy2:2000-2003:4" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest
```

## 🎨 自定义配置

### 高级配置选项

```bash
# 自定义 Reality 伪装域名
-e REALITY_SERVER_NAME="www.amazon.com"

# 设置固定密码
-e HY2_PASSWORD="your-hysteria2-password"
-e TROJAN_PASSWORD="your-trojan-password"

# 调整日志级别
-e LOG_LEVEL="debug"

# 自定义 Shadowsocks 加密方式
-e SS_METHOD="2022-blake3-aes-128-gcm"
```

### 配置文件挂载

```bash
# 使用外部配置文件 (高级用户)
docker run -d \
  -v ./my-config.json:/etc/sing-box/config.json:ro \
  sing-box:latest run -c /etc/sing-box/config.json
```

## 📈 扩展部署

### 多实例部署

```bash
# 实例1: Reality 集群
docker run -d --name reality-cluster \
  -p 1000-1019:1000-1019 \
  -e MULTI_PROTOCOL_CONFIG="reality:1000-1019:20" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest

# 实例2: Hysteria2 集群
docker run -d --name hy2-cluster \
  -p 2000-2019:2000-2019/udp \
  -e MULTI_PROTOCOL_CONFIG="hy2:2000-2019:20" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest
```

### 负载均衡配置

```bash
# 多个相同配置的容器
for i in {1..3}; do
  docker run -d --name singbox-$i \
    -p $((1000+i*100))-$((1003+i*100)):$((1000+i*100))-$((1003+i*100)) \
    -p $((2000+i*100))-$((2003+i*100)):$((2000+i*100))-$((2003+i*100))/udp \
    -e MULTI_PROTOCOL_CONFIG="reality:$((1000+i*100))-$((1003+i*100)):4,hy2:$((2000+i*100))-$((2003+i*100)):4" \
    --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
    sing-box:latest
done
```

---

## 🎉 总结

这个多协议方案完全满足你的需求：

1. ✅ **完美支持你的场景**: Reality 1000-1003，Hysteria2 2000-2003
2. ✅ **超级简化操作**: 一行命令或交互式脚本完成部署
3. ✅ **高度灵活配置**: 支持任意协议和端口范围组合
4. ✅ **智能自动化**: 自动生成密钥、UUID、密码
5. ✅ **完整管理工具**: 配置预览、冲突检测、部署验证

使用 `./docker/multi-deploy.sh` 开始你的多协议之旅！🚀