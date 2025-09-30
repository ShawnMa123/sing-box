#!/bin/bash

# 多协议多端口快速部署脚本
# 简化多协议部署的交互式工具

set -e

# 加载平台兼容性工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform-utils.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
log_highlight() { echo -e "${MAGENTA}[HIGHLIGHT]${NC} $1"; }

# 支持的协议
PROTOCOLS=("reality" "hy2" "trojan" "ss")
PROTOCOL_NAMES=("VLESS Reality" "Hysteria2" "Trojan" "Shadowsocks")

# 预定义配置模板
declare -A PRESET_CONFIGS=(
    ["基础双协议"]="reality:1000-1003:4,hy2:2000-2003:4"
    ["全协议测试"]="reality:1000-1001:2,hy2:2000-2001:2,trojan:3000-3001:2,ss:4000-4001:2"
    ["高密度Reality"]="reality:10000-10019:20"
    ["Reality+Hysteria2集群"]="reality:443-462:20,hy2:8443-8462:20"
    ["分离端口部署"]="reality:1000,1002,1004,1006:4,hy2:2000,2002,2004,2006:4"
)

# 显示欢迎信息
show_welcome() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║               🚀 Sing-Box 多协议部署工具                        ║
║                                                              ║
║   支持一键部署多个协议到不同端口范围                              ║
║   简化配置，快速启动，完美替代 install.sh                         ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# 显示协议选择菜单
show_protocol_menu() {
    echo "支持的协议:"
    for i in "${!PROTOCOLS[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${YELLOW}${PROTOCOLS[i]}${NC} - ${PROTOCOL_NAMES[i]}"
    done
    echo
}

# 显示预设配置
show_preset_configs() {
    log_step "预设配置模板:"
    local i=1
    for name in "${!PRESET_CONFIGS[@]}"; do
        echo -e "  ${CYAN}$i)${NC} ${YELLOW}$name${NC}"
        echo -e "     配置: ${PRESET_CONFIGS[$name]}"
        ((i++))
    done
    echo -e "  ${CYAN}$i)${NC} ${YELLOW}自定义配置${NC}"
    echo
}

# 验证端口范围
validate_port_range() {
    local range="$1"

    if [[ "$range" =~ ^[0-9]+$ ]]; then
        # 单端口
        if [[ $range -lt 1 || $range -gt 65535 ]]; then
            return 1
        fi
    elif [[ "$range" =~ ^[0-9]+-[0-9]+$ ]]; then
        # 端口范围
        local start=$(echo "$range" | cut -d'-' -f1)
        local end=$(echo "$range" | cut -d'-' -f2)
        if [[ $start -lt 1 || $end -gt 65535 || $start -ge $end ]]; then
            return 1
        fi
    else
        return 1
    fi
    return 0
}

# 检查端口冲突
check_port_conflicts() {
    local config="$1"
    local used_ports=()

    IFS=',' read -ra CONFIGS <<< "$config"

    for cfg in "${CONFIGS[@]}"; do
        IFS=':' read -ra PARTS <<< "$cfg"
        local port_range="${PARTS[1]}"
        local count="${PARTS[2]}"

        # 解析端口范围
        if [[ "$port_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((port=start; port<=end && ${#used_ports[@]}<count; port++)); do
                if [[ " ${used_ports[@]} " =~ " $port " ]]; then
                    log_error "端口冲突: $port"
                    return 1
                fi
                used_ports+=($port)
            done
        elif [[ "$port_range" =~ ^[0-9]+$ ]]; then
            if [[ " ${used_ports[@]} " =~ " $port_range " ]]; then
                log_error "端口冲突: $port_range"
                return 1
            fi
            used_ports+=($port_range)
        fi
    done

    return 0
}

# 交互式创建自定义配置
create_custom_config() {
    local config_parts=()

    while true; do
        echo
        log_step "添加协议配置 (第 $((${#config_parts[@]}+1)) 个)"

        # 选择协议
        show_protocol_menu
        while true; do
            read -p "选择协议 (1-${#PROTOCOLS[@]}): " protocol_choice
            if [[ "$protocol_choice" =~ ^[1-${#PROTOCOLS[@]}]$ ]]; then
                selected_protocol="${PROTOCOLS[$((protocol_choice-1))]}"
                break
            else
                log_error "请输入有效选项 (1-${#PROTOCOLS[@]})"
            fi
        done

        # 配置端口范围
        while true; do
            echo
            log_info "端口配置格式:"
            log_info "  单端口: 1000"
            log_info "  端口范围: 1000-1003"
            echo
            read -p "输入 $selected_protocol 的端口范围: " port_range

            if validate_port_range "$port_range"; then
                break
            else
                log_error "无效的端口范围格式"
            fi
        done

        # 配置端口数量
        while true; do
            if [[ "$port_range" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=$(echo "$port_range" | cut -d'-' -f1)
                local end=$(echo "$port_range" | cut -d'-' -f2)
                local max_count=$((end - start + 1))
                log_info "端口范围 $port_range 最多可配置 $max_count 个端口"
                read -p "输入要配置的端口数量 (1-$max_count): " count

                if [[ "$count" =~ ^[1-9][0-9]*$ ]] && [[ $count -le $max_count ]]; then
                    break
                else
                    log_error "请输入 1 到 $max_count 之间的数字"
                fi
            else
                count=1
                break
            fi
        done

        # 添加到配置
        config_parts+=("$selected_protocol:$port_range:$count")

        log_success "已添加: $selected_protocol:$port_range:$count"

        # 询问是否继续
        echo
        read -p "是否添加更多协议? (y/n): " add_more
        if [[ ! "$add_more" =~ ^[yY]$ ]]; then
            break
        fi
    done

    # 生成最终配置
    CUSTOM_CONFIG=$(IFS=','; echo "${config_parts[*]}")

    # 检查端口冲突
    if ! check_port_conflicts "$CUSTOM_CONFIG"; then
        log_error "配置中存在端口冲突，请重新配置"
        return 1
    fi

    log_success "自定义配置生成完成: $CUSTOM_CONFIG"
    return 0
}

# 选择配置模式
select_config_mode() {
    while true; do
        echo
        log_step "选择配置模式:"
        echo -e "  ${CYAN}1)${NC} 使用预设配置模板"
        echo -e "  ${CYAN}2)${NC} 创建自定义配置"
        echo

        read -p "请选择 (1-2): " mode_choice

        case "$mode_choice" in
            1)
                select_preset_config
                return $?
                ;;
            2)
                create_custom_config
                return $?
                ;;
            *)
                log_error "请输入有效选项 (1-2)"
                ;;
        esac
    done
}

# 选择预设配置
select_preset_config() {
    while true; do
        show_preset_configs

        local preset_names=($(printf '%s\n' "${!PRESET_CONFIGS[@]}" | sort))
        local total_presets=${#preset_names[@]}

        read -p "请选择配置 (1-$((total_presets+1))): " preset_choice

        if [[ "$preset_choice" =~ ^[1-$total_presets]$ ]]; then
            local selected_preset="${preset_names[$((preset_choice-1))]}"
            SELECTED_CONFIG="${PRESET_CONFIGS[$selected_preset]}"
            log_success "已选择预设: $selected_preset"
            log_info "配置内容: $SELECTED_CONFIG"
            return 0
        elif [[ "$preset_choice" == "$((total_presets+1))" ]]; then
            create_custom_config
            SELECTED_CONFIG="$CUSTOM_CONFIG"
            return $?
        else
            log_error "请输入有效选项 (1-$((total_presets+1)))"
        fi
    done
}

# 生成端口映射
generate_port_mappings() {
    local config="$1"
    local mappings=()

    IFS=',' read -ra CONFIGS <<< "$config"

    for cfg in "${CONFIGS[@]}"; do
        IFS=':' read -ra PARTS <<< "$cfg"
        local protocol="${PARTS[0]}"
        local port_range="${PARTS[1]}"
        local count="${PARTS[2]}"

        # 确定协议类型 (TCP/UDP)
        local proto_suffix=""
        if [[ "$protocol" == "hy2" ]]; then
            proto_suffix="/udp"
        fi

        # 解析端口范围
        if [[ "$port_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((i=0, port=start; i<count && port<=end; i++, port++)); do
                mappings+=("$port:$port$proto_suffix")
            done
        elif [[ "$port_range" =~ ^[0-9]+$ ]]; then
            mappings+=("$port_range:$port_range$proto_suffix")
        fi
    done

    echo "${mappings[@]}"
}

# 生成Docker Compose端口映射 (YAML格式)
generate_compose_port_mappings() {
    local config="$1"
    local mappings=()

    IFS=',' read -ra CONFIGS <<< "$config"

    for cfg in "${CONFIGS[@]}"; do
        IFS=':' read -ra PARTS <<< "$cfg"
        local protocol="${PARTS[0]}"
        local port_range="${PARTS[1]}"
        local count="${PARTS[2]}"

        # 确定协议类型 (TCP/UDP)
        local proto_suffix=""
        if [[ "$protocol" == "hy2" ]]; then
            proto_suffix="/udp"
        fi

        # 解析端口范围
        if [[ "$port_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((i=0, port=start; i<count && port<=end; i++, port++)); do
                mappings+=("\"$port:$port$proto_suffix\"")
            done
        elif [[ "$port_range" =~ ^[0-9]+$ ]]; then
            mappings+=("\"$port_range:$port_range$proto_suffix\"")
        fi
    done

    printf '%s\n' "${mappings[@]}"
}

# 生成docker run命令
generate_docker_command() {
    local config="$1"
    local container_name="${2:-singbox-multi}"

    local port_mappings=($(generate_port_mappings "$config"))

    echo "docker run -d \\"
    echo "  --name $container_name \\"

    for mapping in "${port_mappings[@]}"; do
        echo "  -p $mapping \\"
    done

    echo "  -e MULTI_PROTOCOL_CONFIG=\"$config\" \\"
    echo "  -e LOG_LEVEL=\"info\" \\"
    echo "  -e REALITY_SERVER_NAME=\"www.cloudflare.com\" \\"
    echo "  -v ./data/logs:/var/log/sing-box \\"
    echo "  -v ./data/config:/etc/sing-box \\"
    echo "  --entrypoint /opt/sing-box/scripts/entrypoint-multi.sh \\"
    echo "  sing-box:latest run -c /etc/sing-box/config.json"
}

# 生成docker-compose配置
generate_compose_config() {
    local config="$1"
    local service_name="${2:-singbox-multi}"

    cat << EOF
version: '3.8'

services:
  $service_name:
    build: .
    container_name: $service_name
    environment:
      MULTI_PROTOCOL_CONFIG: "$config"
      LOG_LEVEL: "info"
      REALITY_SERVER_NAME: "www.cloudflare.com"
    ports:
EOF

    # 使用专门的Compose端口映射函数
    generate_compose_port_mappings "$config" | while read -r mapping; do
        echo "      - $mapping"
    done

    cat << EOF
    volumes:
      - ./data/$service_name/logs:/var/log/sing-box
      - ./data/$service_name/config:/etc/sing-box
    entrypoint: ["/opt/sing-box/scripts/entrypoint-multi.sh"]
    command: ["run", "-c", "/etc/sing-box/config.json"]
    restart: unless-stopped
    networks:
      - singbox-network

networks:
  singbox-network:
    driver: bridge
EOF
}

# 部署服务
deploy_service() {
    local config="$1"
    local deploy_method="$2"

    log_step "开始部署服务..."

    case "$deploy_method" in
        "docker-run")
            log_info "使用 docker run 部署..."
            local cmd=$(generate_docker_command "$config" "singbox-multi-$(date +%s)")
            echo
            log_highlight "执行命令:"
            echo "$cmd"
            echo

            read -p "是否执行此命令? (y/n): " confirm
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                eval "$cmd"
                log_success "容器启动成功!"
            fi
            ;;
        "docker-compose")
            log_info "使用 docker-compose 部署..."
            local compose_file="docker-compose.generated.yml"

            generate_compose_config "$config" > "$compose_file"
            log_success "生成配置文件: $compose_file"

            read -p "是否启动服务? (y/n): " confirm
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                if run_docker_compose -f "$compose_file" up -d; then
                    log_success "服务启动成功!"
                else
                    log_error "服务启动失败"
                    suggest_dependencies
                    exit 1
                fi
            fi
            ;;
    esac
}

# 显示部署结果
show_deployment_result() {
    local config="$1"

    echo
    log_success "🎉 部署完成!"
    echo
    log_highlight "配置信息:"
    log_info "  多协议配置: $config"

    # 解析并显示端口信息
    log_info "  端口分布:"
    IFS=',' read -ra CONFIGS <<< "$config"
    for cfg in "${CONFIGS[@]}"; do
        IFS=':' read -ra PARTS <<< "$cfg"
        local protocol="${PARTS[0]}"
        local port_range="${PARTS[1]}"
        local count="${PARTS[2]}"
        log_info "    $protocol: $port_range (配置 $count 个端口)"
    done

    echo
    log_highlight "管理命令:"
    log_info "  查看日志: docker logs <container_name>"
    log_info "  查看配置: docker exec <container_name> cat /etc/sing-box/config.json"
    log_info "  获取连接信息: docker logs <container_name> 2>&1 | grep -E '(UUID|公钥|密码)'"
    log_info "  重启服务: docker restart <container_name>"
}

# 主函数
main() {
    show_welcome

    # 检查依赖
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        suggest_dependencies
        exit 1
    fi

    # 检查Docker Compose (仅在需要时检查)
    if ! detect_docker_compose &> /dev/null; then
        log_warn "Docker Compose 不可用，将只提供 Docker Run 选项"
    fi

    # 选择配置
    if ! select_config_mode; then
        log_error "配置选择失败"
        exit 1
    fi

    # 显示配置预览
    echo
    log_step "配置预览:"
    log_info "最终配置: $SELECTED_CONFIG"

    # 检查端口冲突
    if ! check_port_conflicts "$SELECTED_CONFIG"; then
        exit 1
    fi

    # 选择部署方式
    echo
    log_step "选择部署方式:"
    echo -e "  ${CYAN}1)${NC} Docker Run (直接运行)"

    local has_compose=false
    if detect_docker_compose &> /dev/null; then
        echo -e "  ${CYAN}2)${NC} Docker Compose (推荐)"
        has_compose=true
    else
        echo -e "  ${CYAN}2)${NC} Docker Compose (不可用 - 未安装)"
    fi
    echo

    while true; do
        if [[ "$has_compose" == "true" ]]; then
            read -p "请选择 (1-2): " deploy_choice
            case "$deploy_choice" in
                1)
                    deploy_service "$SELECTED_CONFIG" "docker-run"
                    break
                    ;;
                2)
                    deploy_service "$SELECTED_CONFIG" "docker-compose"
                    break
                    ;;
                *)
                    log_error "请输入有效选项 (1-2)"
                    ;;
            esac
        else
            log_warn "Docker Compose 不可用，自动使用 Docker Run"
            deploy_service "$SELECTED_CONFIG" "docker-run"
            break
        fi
    done

    # 显示部署结果
    show_deployment_result "$SELECTED_CONFIG"
}

# 执行主函数
main "$@"