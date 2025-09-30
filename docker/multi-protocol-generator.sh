#!/bin/bash

# 多协议多端口配置生成器
# 支持在单个容器中部署多个协议，每个协议使用不同端口范围

set -e

CONFIG_FILE="/etc/sing-box/config.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 生成UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 生成Reality密钥对
generate_reality_keys() {
    local keys=$(/opt/sing-box/bin/sing-box generate reality-keypair)
    echo "$keys" | grep "PrivateKey:" | cut -d' ' -f2
    echo "$keys" | grep "PublicKey:" | cut -d' ' -f2
}

# 生成SS2022密码
generate_ss2022_password() {
    local method="$1"
    case "$method" in
        *aes-128*)
            openssl rand -base64 16
            ;;
        *aes-256*|*chacha20*)
            openssl rand -base64 32
            ;;
        *)
            openssl rand -base64 32
            ;;
    esac
}

# 解析端口范围
parse_port_range() {
    local range="$1"
    if [[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        echo "$start $end"
    elif [[ "$range" =~ ^[0-9]+$ ]]; then
        echo "$range $range"
    else
        log_error "无效的端口范围格式: $range"
        exit 1
    fi
}

# 生成端口列表
generate_port_list() {
    local range_str="$1"
    local count="$2"

    read start_port end_port <<< $(parse_port_range "$range_str")

    local ports=()
    local available_count=$((end_port - start_port + 1))

    if [[ $count -gt $available_count ]]; then
        log_warn "请求的端口数量($count)超过可用范围($available_count)，使用所有可用端口"
        count=$available_count
    fi

    for ((i=0; i<count; i++)); do
        ports[$i]=$((start_port + i))
    done

    echo "${ports[@]}"
}

# 生成VLESS Reality配置
generate_vless_reality_inbound() {
    local port="$1"
    local uuid="$2"
    local private_key="$3"
    local server_name="${4:-www.cloudflare.com}"
    local flow="${5:-xtls-rprx-vision}"

    cat << EOF
{
  "tag": "vless-reality-$port",
  "type": "vless",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "uuid": "$uuid",
      "flow": "$flow"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "$server_name",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "$server_name",
        "server_port": 443
      },
      "private_key": "$private_key",
      "short_id": [""]
    }
  },
  "sniff": true,
  "sniff_override_destination": true
}
EOF
}

# 生成Hysteria2配置
generate_hysteria2_inbound() {
    local port="$1"
    local password="$2"

    cat << EOF
{
  "tag": "hysteria2-$port",
  "type": "hysteria2",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "password": "$password"
    }
  ],
  "tls": {
    "enabled": true,
    "alpn": ["h3"]
  },
  "sniff": true,
  "sniff_override_destination": true
}
EOF
}

# 生成Trojan配置
generate_trojan_inbound() {
    local port="$1"
    local password="$2"

    cat << EOF
{
  "tag": "trojan-$port",
  "type": "trojan",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "password": "$password"
    }
  ],
  "tls": {
    "enabled": true,
    "alpn": ["h2", "http/1.1"]
  },
  "sniff": true,
  "sniff_override_destination": true
}
EOF
}

# 生成Shadowsocks配置
generate_shadowsocks_inbound() {
    local port="$1"
    local method="$2"
    local password="$3"

    cat << EOF
{
  "tag": "shadowsocks-$port",
  "type": "shadowsocks",
  "listen": "::",
  "listen_port": $port,
  "method": "$method",
  "password": "$password",
  "sniff": true,
  "sniff_override_destination": true
}
EOF
}

# 生成基础配置
generate_base_config() {
    cat << EOF
{
  "log": {
    "output": "/var/log/sing-box/access.log",
    "level": "${LOG_LEVEL:-info}",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "8.8.8.8"
      },
      {
        "tag": "cloudflare",
        "address": "1.1.1.1"
      }
    ],
    "rules": [
      {
        "domain_suffix": [".cn"],
        "server": "google"
      }
    ],
    "independent_cache": true
  },
  "ntp": {
    "enabled": true,
    "server": "time.apple.com"
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    }
  ]
}
EOF
}

# 处理协议配置
process_protocol_config() {
    local protocol="$1"
    local port_config="$2"
    local count="$3"

    case "$protocol" in
        vless-reality|reality)
            process_reality_config "$port_config" "$count"
            ;;
        hysteria2|hy2)
            process_hysteria2_config "$port_config" "$count"
            ;;
        trojan)
            process_trojan_config "$port_config" "$count"
            ;;
        shadowsocks|ss)
            process_shadowsocks_config "$port_config" "$count"
            ;;
        *)
            log_error "不支持的协议: $protocol"
            exit 1
            ;;
    esac
}

# 处理Reality配置
process_reality_config() {
    local port_config="$1"
    local count="$2"

    log_info "配置 VLESS Reality，端口范围: $port_config，数量: $count"

    # 生成密钥对
    local keys=($(generate_reality_keys))
    local private_key="${keys[0]}"
    local public_key="${keys[1]}"

    # 生成端口列表
    local ports=($(generate_port_list "$port_config" "$count"))

    # 为每个端口生成配置
    for port in "${ports[@]}"; do
        local uuid=$(generate_uuid)
        local inbound=$(generate_vless_reality_inbound "$port" "$uuid" "$private_key" "${REALITY_SERVER_NAME:-www.cloudflare.com}")

        # 添加到配置文件
        local temp_config=$(jq --argjson inbound "$inbound" '.inbounds += [$inbound]' "$CONFIG_FILE")
        echo "$temp_config" > "$CONFIG_FILE"

        log_success "Reality 端口 $port 配置完成，UUID: $uuid"
    done

    log_info "Reality 公钥: $public_key"
    echo "REALITY_PUBLIC_KEY=$public_key" >> /tmp/connection_info
}

# 处理Hysteria2配置
process_hysteria2_config() {
    local port_config="$1"
    local count="$2"

    log_info "配置 Hysteria2，端口范围: $port_config，数量: $count"

    local ports=($(generate_port_list "$port_config" "$count"))

    for port in "${ports[@]}"; do
        local password="${HY2_PASSWORD:-$(openssl rand -base64 16)}"
        local inbound=$(generate_hysteria2_inbound "$port" "$password")

        local temp_config=$(jq --argjson inbound "$inbound" '.inbounds += [$inbound]' "$CONFIG_FILE")
        echo "$temp_config" > "$CONFIG_FILE"

        log_success "Hysteria2 端口 $port 配置完成，密码: $password"
        echo "HY2_PORT_${port}_PASSWORD=$password" >> /tmp/connection_info
    done
}

# 处理Trojan配置
process_trojan_config() {
    local port_config="$1"
    local count="$2"

    log_info "配置 Trojan，端口范围: $port_config，数量: $count"

    local ports=($(generate_port_list "$port_config" "$count"))

    for port in "${ports[@]}"; do
        local password="${TROJAN_PASSWORD:-$(openssl rand -base64 16)}"
        local inbound=$(generate_trojan_inbound "$port" "$password")

        local temp_config=$(jq --argjson inbound "$inbound" '.inbounds += [$inbound]' "$CONFIG_FILE")
        echo "$temp_config" > "$CONFIG_FILE"

        log_success "Trojan 端口 $port 配置完成，密码: $password"
        echo "TROJAN_PORT_${port}_PASSWORD=$password" >> /tmp/connection_info
    done
}

# 处理Shadowsocks配置
process_shadowsocks_config() {
    local port_config="$1"
    local count="$2"

    log_info "配置 Shadowsocks，端口范围: $port_config，数量: $count"

    local ports=($(generate_port_list "$port_config" "$count"))
    local method="${SS_METHOD:-2022-blake3-aes-256-gcm}"

    for port in "${ports[@]}"; do
        local password
        if [[ "$method" =~ 2022 ]]; then
            password=$(generate_ss2022_password "$method")
        else
            password="${SS_PASSWORD:-$(openssl rand -base64 16)}"
        fi

        local inbound=$(generate_shadowsocks_inbound "$port" "$method" "$password")

        local temp_config=$(jq --argjson inbound "$inbound" '.inbounds += [$inbound]' "$CONFIG_FILE")
        echo "$temp_config" > "$CONFIG_FILE"

        log_success "Shadowsocks 端口 $port 配置完成，方法: $method，密码: $password"
        echo "SS_PORT_${port}_METHOD=$method" >> /tmp/connection_info
        echo "SS_PORT_${port}_PASSWORD=$password" >> /tmp/connection_info
    done
}

# 主函数
main() {
    log_info "开始生成多协议配置..."

    # 生成基础配置
    generate_base_config > "$CONFIG_FILE"

    # 清空连接信息文件
    > /tmp/connection_info

    # 处理协议配置
    # 格式: PROTOCOL_CONFIG="protocol:port_range:count,protocol:port_range:count"
    # 示例: "reality:1000-1003:4,hy2:2000-2003:4"

    if [[ -n "$MULTI_PROTOCOL_CONFIG" ]]; then
        IFS=',' read -ra CONFIGS <<< "$MULTI_PROTOCOL_CONFIG"

        for config in "${CONFIGS[@]}"; do
            IFS=':' read -ra PARTS <<< "$config"
            if [[ ${#PARTS[@]} -eq 3 ]]; then
                local protocol="${PARTS[0]}"
                local port_range="${PARTS[1]}"
                local count="${PARTS[2]}"

                process_protocol_config "$protocol" "$port_range" "$count"
            else
                log_error "无效的配置格式: $config"
                log_error "正确格式: protocol:port_range:count"
                exit 1
            fi
        done
    else
        log_error "未找到 MULTI_PROTOCOL_CONFIG 环境变量"
        log_error "示例: MULTI_PROTOCOL_CONFIG=\"reality:1000-1003:4,hy2:2000-2003:4\""
        exit 1
    fi

    log_success "多协议配置生成完成"

    # 显示统计信息
    local inbound_count=$(jq '.inbounds | length' "$CONFIG_FILE")
    log_info "总共配置了 $inbound_count 个入站连接"

    # 显示端口信息
    log_info "配置的端口列表:"
    jq -r '.inbounds[] | "  - \(.tag): \(.listen_port)"' "$CONFIG_FILE"
}

# 执行主函数
main "$@"