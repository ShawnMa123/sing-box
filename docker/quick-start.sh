#!/bin/bash

# Sing-Box Docker 快速启动脚本
# 提供交互式配置和快速部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 支持的协议列表
PROTOCOLS=(
    "vless-reality"
    "trojan"
    "vmess-ws-tls"
    "shadowsocks"
    "hysteria2"
    "tuic"
    "socks"
)

# 协议描述
declare -A PROTOCOL_DESC=(
    ["vless-reality"]="VLESS Reality - 最新抗审查技术，推荐使用"
    ["trojan"]="Trojan - 经典TLS伪装协议"
    ["vmess-ws-tls"]="VMess WebSocket - 兼容性好的选择"
    ["shadowsocks"]="Shadowsocks - 轻量级代理协议"
    ["hysteria2"]="Hysteria2 - 基于QUIC的高速协议"
    ["tuic"]="TUIC - QUIC代理协议"
    ["socks"]="Socks5 - 标准代理协议"
)

# 默认端口
declare -A DEFAULT_PORTS=(
    ["vless-reality"]="443"
    ["trojan"]="8443"
    ["vmess-ws-tls"]="8080"
    ["shadowsocks"]="8388"
    ["hysteria2"]="36712"
    ["tuic"]="8443"
    ["socks"]="1080"
)

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# 生成UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# 生成随机端口
generate_random_port() {
    shuf -i 10000-65535 -n 1
}

# 生成强密码
generate_password() {
    if command -v openssl &> /dev/null; then
        openssl rand -base64 16
    else
        head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16
    fi
}

# 显示欢迎信息
show_welcome() {
    clear
    cat << 'EOF'
 ____  _                ____
/ ___|(_)_ __   __ _   | __ )  _____  __
\___ \| | '_ \ / _` |  |  _ \ / _ \ \/ /
 ___) | | | | | (_| |  | |_) | (_) >  <
|____/|_|_| |_|\__, |  |____/ \___/_/\_\
               |___/

🚀 Sing-Box Docker 快速启动工具

EOF
    echo -e "基于官方 install.sh 的 Docker 容器化部署方案"
    echo -e "支持所有主流代理协议，通过环境变量灵活配置"
    echo
}

# 选择协议
select_protocol() {
    log_step "选择代理协议"
    echo

    local i=1
    for protocol in "${PROTOCOLS[@]}"; do
        echo -e "  ${CYAN}$i)${NC} ${YELLOW}$protocol${NC} - ${PROTOCOL_DESC[$protocol]}"
        ((i++))
    done

    echo
    while true; do
        read -p "请选择协议 (1-${#PROTOCOLS[@]}): " choice
        if [[ "$choice" =~ ^[1-${#PROTOCOLS[@]}]$ ]]; then
            SELECTED_PROTOCOL="${PROTOCOLS[$((choice-1))]}"
            break
        else
            log_error "请输入有效的选项 (1-${#PROTOCOLS[@]})"
        fi
    done

    log_success "已选择协议: $SELECTED_PROTOCOL"
    echo
}

# 配置端口
configure_port() {
    log_step "配置服务端口"

    local default_port="${DEFAULT_PORTS[$SELECTED_PROTOCOL]}"

    while true; do
        read -p "请输入端口 (回车使用默认 $default_port): " port
        port=${port:-$default_port}

        if [[ "$port" =~ ^[1-9][0-9]*$ ]] && [[ "$port" -le 65535 ]]; then
            # 检查端口是否被占用
            if command -v ss &> /dev/null; then
                if ss -tulpn | grep -q ":$port "; then
                    log_warn "端口 $port 可能已被占用"
                    read -p "是否继续使用此端口? (y/n): " confirm
                    [[ "$confirm" =~ ^[yY]$ ]] && break
                else
                    break
                fi
            else
                log_warn "无法检测端口占用情况，将使用端口 $port"
                break
            fi
        else
            log_error "请输入有效的端口号 (1-65535)"
        fi
    done

    SELECTED_PORT="$port"
    log_success "已配置端口: $SELECTED_PORT"
    echo
}

# 协议特定配置
configure_protocol_specific() {
    case "$SELECTED_PROTOCOL" in
        vless-reality)
            configure_vless_reality
            ;;
        trojan*)
            configure_trojan
            ;;
        vmess*)
            configure_vmess
            ;;
        shadowsocks)
            configure_shadowsocks
            ;;
        hysteria2|tuic)
            configure_tuic_hysteria2
            ;;
        socks)
            configure_socks
            ;;
    esac
}

# VLESS Reality 配置
configure_vless_reality() {
    log_step "配置 VLESS Reality"

    # UUID
    local default_uuid=$(generate_uuid)
    read -p "请输入 UUID (回车自动生成): " uuid
    UUID=${uuid:-$default_uuid}

    # 伪装域名
    local servernames=("www.cloudflare.com" "www.amazon.com" "www.microsoft.com" "www.apple.com")
    echo "推荐的伪装域名:"
    for i in "${!servernames[@]}"; do
        echo "  $((i+1))) ${servernames[i]}"
    done

    read -p "请选择或输入伪装域名 (回车使用 www.cloudflare.com): " servername_choice
    if [[ "$servername_choice" =~ ^[1-4]$ ]]; then
        SERVER_NAME="${servernames[$((servername_choice-1))]}"
    elif [[ -n "$servername_choice" ]]; then
        SERVER_NAME="$servername_choice"
    else
        SERVER_NAME="www.cloudflare.com"
    fi

    log_success "Reality 配置完成"
    log_info "UUID: $UUID"
    log_info "伪装域名: $SERVER_NAME"
    echo
}

# Trojan 配置
configure_trojan() {
    log_step "配置 Trojan"

    local default_password=$(generate_password)
    read -p "请输入 Trojan 密码 (回车自动生成): " password
    TROJAN_PASSWORD=${password:-$default_password}

    log_success "Trojan 配置完成"
    log_info "密码: $TROJAN_PASSWORD"
    echo
}

# VMess 配置
configure_vmess() {
    log_step "配置 VMess"

    local default_uuid=$(generate_uuid)
    read -p "请输入 UUID (回车自动生成): " uuid
    UUID=${uuid:-$default_uuid}

    read -p "请输入 WebSocket 路径 (回车使用 /vmess): " ws_path
    WS_PATH=${ws_path:-"/vmess"}

    read -p "请输入 Host 头 (可选): " host_header
    HOST_HEADER="$host_header"

    log_success "VMess 配置完成"
    log_info "UUID: $UUID"
    log_info "WebSocket 路径: $WS_PATH"
    [[ -n "$HOST_HEADER" ]] && log_info "Host 头: $HOST_HEADER"
    echo
}

# Shadowsocks 配置
configure_shadowsocks() {
    log_step "配置 Shadowsocks"

    local methods=("2022-blake3-aes-256-gcm" "2022-blake3-aes-128-gcm" "aes-256-gcm" "chacha20-ietf-poly1305")
    echo "加密方式:"
    for i in "${!methods[@]}"; do
        echo "  $((i+1))) ${methods[i]}"
    done

    read -p "请选择加密方式 (回车使用 2022-blake3-aes-256-gcm): " method_choice
    if [[ "$method_choice" =~ ^[1-4]$ ]]; then
        SS_METHOD="${methods[$((method_choice-1))]}"
    else
        SS_METHOD="2022-blake3-aes-256-gcm"
    fi

    local default_password=$(generate_password)
    read -p "请输入密码 (回车自动生成): " password
    SS_PASSWORD=${password:-$default_password}

    log_success "Shadowsocks 配置完成"
    log_info "加密方式: $SS_METHOD"
    log_info "密码: $SS_PASSWORD"
    echo
}

# TUIC/Hysteria2 配置
configure_tuic_hysteria2() {
    log_step "配置 $SELECTED_PROTOCOL"

    local default_uuid=$(generate_uuid)
    read -p "请输入 UUID (回车自动生成): " uuid
    UUID=${uuid:-$default_uuid}

    local default_password=$(generate_password)
    read -p "请输入密码 (回车自动生成): " password
    TUIC_PASSWORD=${password:-$default_password}

    log_success "$SELECTED_PROTOCOL 配置完成"
    log_info "UUID: $UUID"
    log_info "密码: $TUIC_PASSWORD"
    echo
}

# Socks 配置
configure_socks() {
    log_step "配置 Socks5"

    read -p "请输入用户名 (回车使用 proxyuser): " username
    SOCKS_USER=${username:-"proxyuser"}

    local default_password=$(generate_password)
    read -p "请输入密码 (回车自动生成): " password
    SOCKS_PASS=${password:-$default_password}

    log_success "Socks5 配置完成"
    log_info "用户名: $SOCKS_USER"
    log_info "密码: $SOCKS_PASS"
    echo
}

# 生成 .env 文件
generate_env_file() {
    log_step "生成配置文件"

    cat > .env << EOF
# Sing-Box Docker 配置
# 由快速启动脚本生成 - $(date)

# 基础配置
PROTOCOL=$SELECTED_PROTOCOL
PORT=$SELECTED_PORT
LOG_LEVEL=info

EOF

    # 根据协议添加特定配置
    case "$SELECTED_PROTOCOL" in
        vless-reality)
            cat >> .env << EOF
# VLESS Reality 配置
UUID=$UUID
SERVER_NAME=$SERVER_NAME
TRANSPORT=tcp
FLOW=xtls-rprx-vision

EOF
            ;;
        trojan*)
            cat >> .env << EOF
# Trojan 配置
TROJAN_PASSWORD=$TROJAN_PASSWORD

EOF
            ;;
        vmess*)
            cat >> .env << EOF
# VMess 配置
UUID=$UUID
TRANSPORT=ws
WS_PATH=$WS_PATH
HOST_HEADER=$HOST_HEADER
VMESS_SECURITY=auto

EOF
            ;;
        shadowsocks)
            cat >> .env << EOF
# Shadowsocks 配置
SS_METHOD=$SS_METHOD
SS_PASSWORD=$SS_PASSWORD

EOF
            ;;
        hysteria2|tuic)
            cat >> .env << EOF
# $SELECTED_PROTOCOL 配置
UUID=$UUID
TROJAN_PASSWORD=$TUIC_PASSWORD

EOF
            ;;
        socks)
            cat >> .env << EOF
# Socks5 配置
SOCKS_USER=$SOCKS_USER
SOCKS_PASS=$SOCKS_PASS

EOF
            ;;
    esac

    log_success "配置文件已生成: .env"
    echo
}

# 启动服务
start_service() {
    log_step "启动 Sing-Box 服务"

    # 检查 docker-compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose 未安装"
        exit 1
    fi

    # 确定 profile
    local profile=""
    case "$SELECTED_PROTOCOL" in
        vless-reality) profile="vless-reality" ;;
        trojan*) profile="trojan" ;;
        vmess*) profile="vmess-ws" ;;
        shadowsocks) profile="shadowsocks" ;;
        hysteria2) profile="hysteria2" ;;
        tuic) profile="tuic" ;;
        socks) profile="socks5" ;;
    esac

    # 创建数据目录
    mkdir -p "./data/$profile/"{logs,config}

    # 启动服务
    log_info "正在启动服务..."
    if docker-compose --profile "$profile" up -d; then
        log_success "服务启动成功!"

        # 等待服务就绪
        sleep 3

        # 显示服务状态
        log_info "服务状态:"
        docker-compose ps

        echo
        log_success "🎉 部署完成!"
        show_connection_info
    else
        log_error "服务启动失败"
        exit 1
    fi
}

# 显示连接信息
show_connection_info() {
    local container_name="singbox-${SELECTED_PROTOCOL//_/-}"

    echo
    echo "=== 连接信息 ==="
    echo "协议: $SELECTED_PROTOCOL"
    echo "端口: $SELECTED_PORT"

    case "$SELECTED_PROTOCOL" in
        vless-reality)
            echo "UUID: $UUID"
            echo "伪装域名: $SERVER_NAME"
            echo
            echo "获取 Reality 公钥:"
            echo "  docker logs $container_name 2>&1 | grep '公钥'"
            ;;
        trojan*)
            echo "密码: $TROJAN_PASSWORD"
            ;;
        vmess*)
            echo "UUID: $UUID"
            echo "路径: $WS_PATH"
            [[ -n "$HOST_HEADER" ]] && echo "Host: $HOST_HEADER"
            ;;
        shadowsocks)
            echo "加密方式: $SS_METHOD"
            echo "密码: $SS_PASSWORD"
            ;;
        hysteria2|tuic)
            echo "UUID: $UUID"
            echo "密码: $TUIC_PASSWORD"
            ;;
        socks)
            echo "用户名: $SOCKS_USER"
            echo "密码: $SOCKS_PASS"
            ;;
    esac

    echo
    echo "=== 管理命令 ==="
    echo "查看日志: docker-compose logs -f ${SELECTED_PROTOCOL//_/-}"
    echo "重启服务: docker-compose restart ${SELECTED_PROTOCOL//_/-}"
    echo "停止服务: docker-compose stop ${SELECTED_PROTOCOL//_/-}"
    echo "查看配置: docker exec $container_name cat /etc/sing-box/config.json"
    echo
}

# 主函数
main() {
    # 显示欢迎信息
    show_welcome

    # 检查依赖
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi

    # 交互式配置
    select_protocol
    configure_port
    configure_protocol_specific

    # 生成配置文件
    generate_env_file

    # 确认启动
    echo "=== 配置总结 ==="
    echo "协议: $SELECTED_PROTOCOL"
    echo "端口: $SELECTED_PORT"
    echo "配置文件: .env"
    echo

    read -p "是否立即启动服务? (y/n): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        start_service
    else
        log_info "配置已保存到 .env 文件"
        log_info "手动启动命令: docker-compose --profile ${SELECTED_PROTOCOL//_/-} up -d"
    fi
}

# 执行主函数
main "$@"