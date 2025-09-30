#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 环境变量默认值
PROTOCOL=${PROTOCOL:-"vless-reality"}
PORT=${PORT:-"443"}
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
SERVER_NAME=${SERVER_NAME:-"www.cloudflare.com"}
PRIVATE_KEY=${PRIVATE_KEY:-""}
PUBLIC_KEY=${PUBLIC_KEY:-""}
TRANSPORT=${TRANSPORT:-"tcp"}
FLOW=${FLOW:-"xtls-rprx-vision"}

# Trojan配置
TROJAN_PASSWORD=${TROJAN_PASSWORD:-$UUID}

# Shadowsocks配置
SS_METHOD=${SS_METHOD:-"2022-blake3-aes-256-gcm"}
SS_PASSWORD=${SS_PASSWORD:-$UUID}

# VMess配置
VMESS_SECURITY=${VMESS_SECURITY:-"auto"}

# 传输层配置
WS_PATH=${WS_PATH:-"/$UUID"}
H2_PATH=${H2_PATH:-"/$UUID"}
HOST_HEADER=${HOST_HEADER:-""}

# 其他配置
LOG_LEVEL=${LOG_LEVEL:-"info"}
SNIFF_ENABLED=${SNIFF_ENABLED:-"true"}
SNIFF_OVERRIDE_DESTINATION=${SNIFF_OVERRIDE_DESTINATION:-"true"}

# 生成Reality密钥对
generate_reality_keys() {
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        log_info "生成Reality密钥对..."
        local keys=$(/opt/sing-box/bin/sing-box generate reality-keypair)
        PRIVATE_KEY=$(echo "$keys" | grep "PrivateKey:" | cut -d' ' -f2)
        PUBLIC_KEY=$(echo "$keys" | grep "PublicKey:" | cut -d' ' -f2)
        log_success "Reality密钥对生成完成"
        log_info "私钥: $PRIVATE_KEY"
        log_info "公钥: $PUBLIC_KEY"
    fi
}

# 生成SS2022密码
generate_ss2022_password() {
    if [[ "$SS_METHOD" =~ "2022" && "$SS_PASSWORD" == "$UUID" ]]; then
        case "$SS_METHOD" in
            *aes-128*)
                SS_PASSWORD=$(openssl rand -base64 16)
                ;;
            *aes-256*|*chacha20*)
                SS_PASSWORD=$(openssl rand -base64 32)
                ;;
        esac
        log_info "生成SS2022密码: $SS_PASSWORD"
    fi
}

# 验证端口
validate_port() {
    if [[ ! "$PORT" =~ ^[1-9][0-9]*$ ]] || [[ "$PORT" -gt 65535 ]]; then
        log_error "无效端口: $PORT"
        exit 1
    fi
}

# 验证UUID
validate_uuid() {
    if [[ ! "$UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        log_error "无效UUID格式: $UUID"
        exit 1
    fi
}

# 主配置生成
generate_config() {
    log_info "开始生成sing-box配置..."
    log_info "协议: $PROTOCOL"
    log_info "端口: $PORT"
    log_info "UUID: $UUID"

    # 验证输入
    validate_port
    validate_uuid

    # 特殊处理
    case "$PROTOCOL" in
        *reality*)
            generate_reality_keys
            ;;
        shadowsocks*)
            generate_ss2022_password
            ;;
    esac

    # 调用配置生成脚本
    /opt/sing-box/scripts/config-generator.sh
}

# 显示配置信息
show_config_info() {
    log_success "=== Sing-Box 配置信息 ==="
    log_info "协议: $PROTOCOL"
    log_info "端口: $PORT"
    log_info "UUID: $UUID"

    case "$PROTOCOL" in
        *reality*)
            log_info "ServerName: $SERVER_NAME"
            log_info "公钥: $PUBLIC_KEY"
            ;;
        trojan*)
            log_info "密码: $TROJAN_PASSWORD"
            ;;
        shadowsocks*)
            log_info "加密方式: $SS_METHOD"
            log_info "密码: $SS_PASSWORD"
            ;;
    esac

    if [[ "$TRANSPORT" == "ws" ]]; then
        log_info "WebSocket路径: $WS_PATH"
    elif [[ "$TRANSPORT" == "h2" || "$TRANSPORT" == "http" ]]; then
        log_info "HTTP路径: $H2_PATH"
    fi

    log_success "========================="
}

# 主函数
main() {
    log_info "启动Sing-Box Docker容器..."

    # 生成配置
    generate_config

    # 验证配置
    log_info "验证配置文件..."
    if ! /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json; then
        log_error "配置文件验证失败"
        exit 1
    fi
    log_success "配置文件验证通过"

    # 显示配置信息
    show_config_info

    # 启动sing-box
    log_info "启动sing-box服务..."
    exec /opt/sing-box/bin/sing-box "$@"
}

# 如果第一个参数不是sing-box的标准命令，则运行主函数
case "$1" in
    run|check|version|generate|format|merge|geoip|geosite|rule-set)
        # 如果是run命令，先生成配置
        if [[ "$1" == "run" ]]; then
            generate_config
            show_config_info
        fi
        exec /opt/sing-box/bin/sing-box "$@"
        ;;
    *)
        main "$@"
        ;;
esac