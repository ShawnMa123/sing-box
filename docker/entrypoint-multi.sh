#!/bin/bash
set -e

# 多协议多端口入口脚本
# 支持在单个容器中部署多个协议

# 加载平台兼容性工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/platform-utils.sh" ]]; then
    source "$SCRIPT_DIR/platform-utils.sh"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# 环境变量默认值
LOG_LEVEL=${LOG_LEVEL:-"info"}
SNIFF_ENABLED=${SNIFF_ENABLED:-"true"}
SNIFF_OVERRIDE_DESTINATION=${SNIFF_OVERRIDE_DESTINATION:-"true"}

# Reality配置
REALITY_SERVER_NAME=${REALITY_SERVER_NAME:-"www.cloudflare.com"}

# Shadowsocks配置
SS_METHOD=${SS_METHOD:-"2022-blake3-aes-256-gcm"}

# 检查运行模式
check_mode() {
    if [[ -n "$MULTI_PROTOCOL_CONFIG" ]]; then
        echo "multi"
    elif [[ -n "$PROTOCOL" ]]; then
        echo "single"
    else
        echo "unknown"
    fi
}

# 验证多协议配置格式
validate_multi_config() {
    local config="$1"

    if [[ ! "$config" =~ ^[a-zA-Z0-9_-]+:[0-9]+-?[0-9]*:[0-9]+(,[a-zA-Z0-9_-]+:[0-9]+-?[0-9]*:[0-9]+)*$ ]]; then
        log_error "多协议配置格式错误"
        log_error "正确格式: protocol:port_range:count,protocol:port_range:count"
        log_error "示例: reality:1000-1003:4,hy2:2000-2003:4"
        log_error "当前配置: $config"
        exit 1
    fi
}

# 解析并显示配置预览
show_config_preview() {
    local config="$1"

    log_step "配置预览:"

    IFS=',' read -ra CONFIGS <<< "$config"
    local total_ports=0

    for cfg in "${CONFIGS[@]}"; do
        IFS=':' read -ra PARTS <<< "$cfg"
        local protocol="${PARTS[0]}"
        local port_range="${PARTS[1]}"
        local count="${PARTS[2]}"

        # 解析端口范围
        if [[ "$port_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            local available=$((end - start + 1))
            local actual_count=$([[ $count -le $available ]] && echo $count || echo $available)
        else
            local actual_count=1
        fi

        total_ports=$((total_ports + actual_count))

        log_info "  $protocol: 端口范围 $port_range, 配置 $actual_count 个端口"
    done

    log_info "总端口数: $total_ports"
    echo
}

# 生成多协议配置
generate_multi_config() {
    log_step "生成多协议配置..."

    # 验证配置格式
    validate_multi_config "$MULTI_PROTOCOL_CONFIG"

    # 显示配置预览
    show_config_preview "$MULTI_PROTOCOL_CONFIG"

    # 调用多协议生成器
    /opt/sing-box/scripts/multi-protocol-generator.sh

    if [[ $? -eq 0 ]]; then
        log_success "多协议配置生成完成"
    else
        log_error "多协议配置生成失败"
        exit 1
    fi
}

# 生成单协议配置
generate_single_config() {
    log_step "生成单协议配置..."

    # 调用原有的配置生成器
    /opt/sing-box/scripts/config-generator.sh

    if [[ $? -eq 0 ]]; then
        log_success "单协议配置生成完成"
    else
        log_error "单协议配置生成失败"
        exit 1
    fi
}

# 验证配置文件
verify_config() {
    log_step "验证配置文件..."

    if ! /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json; then
        log_error "配置文件验证失败"
        log_error "配置文件内容:"
        cat /etc/sing-box/config.json
        exit 1
    fi

    log_success "配置文件验证通过"
}

# 显示连接信息
show_connection_info() {
    local mode="$1"

    log_success "=== Sing-Box 多协议部署信息 ==="

    if [[ "$mode" == "multi" ]]; then
        log_info "运行模式: 多协议模式"
        log_info "配置字符串: $MULTI_PROTOCOL_CONFIG"

        # 显示端口统计
        local inbound_count=$(jq '.inbounds | length' /etc/sing-box/config.json)
        log_info "总入站连接数: $inbound_count"

        # 按协议分组显示
        log_info "协议端口分布:"
        jq -r '.inbounds[] | "  \(.type): \(.listen_port) (\(.tag))"' /etc/sing-box/config.json | sort

        # 显示连接参数
        if [[ -f /tmp/connection_info ]]; then
            echo
            log_info "连接参数:"
            while IFS= read -r line; do
                log_info "  $line"
            done < /tmp/connection_info
        fi

    else
        log_info "运行模式: 单协议模式"
        log_info "协议: ${PROTOCOL:-未知}"
        log_info "端口: ${PORT:-未知}"
    fi

    echo
    log_info "容器管理:"
    log_info "  查看日志: docker logs <container_name>"
    log_info "  查看配置: docker exec <container_name> cat /etc/sing-box/config.json"
    log_info "  重启服务: docker restart <container_name>"

    log_success "================================"
}

# 生成端口映射提示
generate_port_mapping_hint() {
    if [[ -f /etc/sing-box/config.json ]]; then
        log_info "Docker端口映射建议:"
        echo "  docker run -d \\"

        jq -r '.inbounds[] | .listen_port' /etc/sing-box/config.json | sort -n | while read port; do
            echo "    -p $port:$port \\"
        done

        echo "    sing-box:latest"
        echo
    fi
}

# 主函数
main() {
    log_info "启动 Sing-Box 多协议容器..."

    # 检查运行模式
    local mode=$(check_mode)

    case "$mode" in
        multi)
            log_info "检测到多协议配置模式"
            generate_multi_config
            ;;
        single)
            log_info "检测到单协议配置模式"
            generate_single_config
            ;;
        *)
            log_error "未检测到有效的配置"
            log_error "请设置以下环境变量之一:"
            log_error "  - MULTI_PROTOCOL_CONFIG: 多协议配置"
            log_error "  - PROTOCOL: 单协议配置"
            log_error ""
            log_error "多协议配置示例:"
            log_error "  MULTI_PROTOCOL_CONFIG=\"reality:1000-1003:4,hy2:2000-2003:4\""
            log_error ""
            log_error "单协议配置示例:"
            log_error "  PROTOCOL=vless-reality"
            log_error "  PORT=443"
            exit 1
            ;;
    esac

    # 验证配置
    verify_config

    # 显示连接信息
    show_connection_info "$mode"

    # 生成端口映射提示
    generate_port_mapping_hint

    # 启动sing-box
    log_info "启动 sing-box 服务..."
    exec /opt/sing-box/bin/sing-box "$@"
}

# 如果第一个参数不是sing-box的标准命令，则运行主函数
case "$1" in
    run|check|version|generate|format|merge|geoip|geosite|rule-set)
        # 如果是run命令，先生成配置
        if [[ "$1" == "run" ]]; then
            local mode=$(check_mode)
            case "$mode" in
                multi)
                    generate_multi_config
                    ;;
                single)
                    generate_single_config
                    ;;
                *)
                    log_error "配置检查失败"
                    exit 1
                    ;;
            esac
            verify_config
            show_connection_info "$mode"
        fi
        exec /opt/sing-box/bin/sing-box "$@"
        ;;
    *)
        main "$@"
        ;;
esac