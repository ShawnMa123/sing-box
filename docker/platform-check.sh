#!/bin/bash

# 平台兼容性检查脚本
# 检查所有必需的命令和工具是否可用

set -e

# 加载平台工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform-utils.sh"

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

# 检查单个命令
check_command() {
    local cmd="$1"
    local desc="$2"
    local required="${3:-false}"

    if command -v "$cmd" &> /dev/null; then
        log_success "$desc: $cmd ($(command -v $cmd))"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            log_error "$desc: 未找到 $cmd (必需)"
            return 1
        else
            log_warn "$desc: 未找到 $cmd (可选)"
            return 0
        fi
    fi
}

# 检查功能
check_function() {
    local func_name="$1"
    local desc="$2"

    if "$func_name" &> /dev/null; then
        log_success "$desc: 可用"
        return 0
    else
        log_error "$desc: 不可用"
        return 1
    fi
}

# 主检查函数
main() {
    echo "=== Sing-Box Docker 平台兼容性检查 ==="
    echo

    # 系统信息
    log_info "操作系统: $(detect_os)"
    log_info "包管理器: $(detect_package_manager)"
    echo

    # 必需工具检查
    log_info "检查必需工具..."
    local required_ok=true

    if ! check_command "docker" "Docker" true; then
        required_ok=false
    fi

    if ! check_command "jq" "JSON处理器" true; then
        required_ok=false
    fi

    echo

    # Docker Compose检查
    log_info "检查Docker Compose..."
    if detect_docker_compose &> /dev/null; then
        local compose_cmd=$(detect_docker_compose)
        log_success "Docker Compose: $compose_cmd"
    else
        log_warn "Docker Compose: 不可用"
        log_info "  提示: 可以只使用 docker run 命令"
    fi

    echo

    # UUID生成检查
    log_info "检查UUID生成..."
    if check_function "detect_uuid_generator" "UUID生成器"; then
        local uuid_method=$(detect_uuid_generator)
        local test_uuid=$(generate_uuid_portable)
        log_success "UUID方法: $uuid_method"
        log_info "测试UUID: $test_uuid"
    fi

    echo

    # 网络工具检查
    log_info "检查网络工具..."
    if detect_network_tool &> /dev/null; then
        local net_tool=$(detect_network_tool)
        log_success "网络工具: $net_tool"
    else
        log_warn "网络工具: 不可用 (无法检测端口占用)"
    fi

    echo

    # 加密工具检查
    log_info "检查加密工具..."
    check_command "openssl" "OpenSSL加密工具" false

    echo

    # 权限检查
    log_info "检查文件权限..."
    if [[ -r /dev/urandom ]]; then
        log_success "随机数生成: /dev/urandom 可读"
    else
        log_warn "随机数生成: /dev/urandom 不可读"
    fi

    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        log_success "系统UUID: /proc/sys/kernel/random/uuid 可读"
    else
        log_warn "系统UUID: /proc/sys/kernel/random/uuid 不可读"
    fi

    echo

    # 总结
    if [[ "$required_ok" == "true" ]]; then
        log_success "✅ 所有必需工具都已安装，可以正常使用！"
    else
        log_error "❌ 缺少必需工具，请安装后再试"
        echo
        suggest_dependencies
        return 1
    fi

    echo
    log_info "建议使用的启动命令:"
    if detect_docker_compose &> /dev/null; then
        echo "  ./docker/multi-deploy.sh (完整交互式部署)"
        echo "  docker-compose -f docker-compose.multi.yml up -d (快速启动)"
    else
        echo "  ./docker/multi-deploy.sh (将自动使用 docker run)"
    fi

    return 0
}

# 执行主函数
main "$@"