# Debian/Ubuntu 系统安装指南

针对Debian/Ubuntu系统的详细安装和使用指南。

## 🚀 快速安装

### 1. 安装依赖

```bash
# 更新包列表
sudo apt update

# 安装基础依赖
sudo apt install -y \
    curl \
    wget \
    git \
    jq \
    uuid-runtime \
    net-tools

# 安装Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 添加用户到docker组 (避免每次使用sudo)
sudo usermod -aG docker $USER

# 重新登录或运行以下命令应用组权限
newgrp docker

# 安装Docker Compose Plugin (推荐方式)
sudo apt install -y docker-compose-plugin

# 或者安装独立的docker-compose (备选方式)
# sudo apt install -y docker-compose
```

### 2. 验证安装

```bash
# 检查Docker
docker --version

# 检查Docker Compose (两种方式都要测试)
docker compose version  # 新版Plugin方式
docker-compose version  # 传统方式

# 检查其他工具
jq --version
uuidgen
```

### 3. 运行兼容性检查

```bash
# 克隆或进入项目目录
cd sing-box

# 运行平台检查
./docker/platform-check.sh
```

## 🔧 常见问题解决

### 问题1: `docker-compose: command not found`

**原因**: 新版Docker使用`docker compose`而不是`docker-compose`

**解决方案**:
```bash
# 方案1: 安装Docker Compose Plugin (推荐)
sudo apt install -y docker-compose-plugin

# 方案2: 安装传统docker-compose
sudo apt install -y docker-compose

# 方案3: 创建软链接 (如果只有新版)
sudo ln -s $(which docker) /usr/local/bin/docker-compose
```

### 问题2: 权限问题

**现象**: `permission denied` 错误

**解决方案**:
```bash
# 将用户添加到docker组
sudo usermod -aG docker $USER

# 重新登录或运行
newgrp docker

# 验证权限
docker ps
```

### 问题3: UUID命令不存在

**解决方案**:
```bash
# 安装uuid工具包
sudo apt install -y uuid-runtime

# 验证
uuidgen
```

### 问题4: jq命令不存在

**解决方案**:
```bash
# 安装jq
sudo apt install -y jq

# 验证
echo '{"test": "value"}' | jq .
```

## 🚀 部署方式

### 方法1: 交互式部署 (推荐)

```bash
# 运行交互式部署脚本
./docker/multi-deploy.sh
```

脚本会自动检测可用的Docker Compose命令并提供相应选项。

### 方法2: 直接使用Docker命令

```bash
# 你的使用场景: Reality + Hysteria2
docker run -d \
  --name singbox-multi \
  -p 34000-34002:34000-34002 \
  -p 35000-35002:35000-35002/udp \
  -e MULTI_PROTOCOL_CONFIG="reality:34000-34002:3,hy2:35000-35002:3" \
  -e REALITY_SERVER_NAME="www.cloudflare.com" \
  -v ./data/logs:/var/log/sing-box \
  -v ./data/config:/etc/sing-box \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest
```

### 方法3: Docker Compose

```bash
# 如果有docker compose命令
docker compose -f docker-compose.multi.yml up -d singbox-multi

# 如果是传统docker-compose
docker-compose -f docker-compose.multi.yml up -d singbox-multi
```

## 📊 系统要求

### 最低要求
- **OS**: Debian 10+ / Ubuntu 18.04+
- **内存**: 512MB RAM
- **存储**: 1GB 可用空间
- **网络**: 公网IP或端口转发

### 推荐配置
- **OS**: Debian 11+ / Ubuntu 20.04+
- **内存**: 1GB+ RAM
- **存储**: 2GB+ 可用空间
- **网络**: 独立公网IP

## 🔍 故障排除

### 检查系统兼容性

```bash
# 运行平台检查脚本
./docker/platform-check.sh

# 输出示例:
# ✅ 所有必需工具都已安装，可以正常使用！
```

### 查看详细错误

```bash
# 查看容器日志
docker logs singbox-multi

# 查看配置文件
docker exec singbox-multi cat /etc/sing-box/config.json

# 检查端口占用
ss -tulpn | grep -E "(34000|35000)"
```

### 重置环境

```bash
# 停止所有容器
docker stop $(docker ps -aq)

# 删除所有容器
docker rm $(docker ps -aq)

# 清理镜像 (可选)
docker rmi $(docker images -q sing-box)

# 重新构建
docker build -t sing-box .
```

## 📚 性能优化

### 网络优化

```bash
# 使用host网络模式 (Linux)
docker run -d --network host \
  -e MULTI_PROTOCOL_CONFIG="reality:34000-34002:3,hy2:35000-35002:3" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest
```

### 资源限制

```bash
# 限制CPU和内存使用
docker run -d \
  --memory=512m \
  --cpus=1.0 \
  --name singbox-multi \
  -e MULTI_PROTOCOL_CONFIG="reality:34000-34002:3,hy2:35000-35002:3" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest
```

## 🔐 安全建议

### 防火墙配置

```bash
# 安装ufw (如果未安装)
sudo apt install -y ufw

# 允许SSH
sudo ufw allow ssh

# 允许你的端口范围
sudo ufw allow 34000:34002/tcp
sudo ufw allow 35000:35002/udp

# 启用防火墙
sudo ufw enable
```

### 系统安全

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 配置自动安全更新
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## 📝 使用示例

### 你的配置场景

```bash
# 构建镜像
docker build -t sing-box .

# 启动服务 (Reality: 34000-34002, Hysteria2: 35000-35002)
./docker/multi-deploy.sh

# 或直接运行
docker run -d \
  --name singbox-multi \
  -p 34000-34002:34000-34002 \
  -p 35000-35002:35000-35002/udp \
  -e MULTI_PROTOCOL_CONFIG="reality:34000-34002:3,hy2:35000-35002:3" \
  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \
  sing-box:latest

# 查看连接信息
docker logs singbox-multi 2>&1 | grep -E "(UUID|公钥|密码)"
```

---

## 🆘 需要帮助？

1. **运行兼容性检查**: `./docker/platform-check.sh`
2. **查看容器日志**: `docker logs singbox-multi`
3. **检查端口占用**: `ss -tulpn | grep 34000`
4. **验证配置**: `docker exec singbox-multi /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json`

现在你的Debian系统应该能够完美运行多协议部署了！🎉