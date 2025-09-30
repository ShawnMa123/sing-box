#!/bin/bash

# 平台兼容性工具函数
# 处理不同操作系统和发行版的命令差异

# 检测Docker Compose命令
detect_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        return 1
    fi
}

# 检测UUID生成命令
detect_uuid_generator() {
    if command -v uuidgen &> /dev/null; then
        echo "uuidgen"
    elif command -v uuid &> /dev/null; then
        echo "uuid"
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        echo "proc"
    else
        return 1
    fi
}

# 生成UUID
generate_uuid_portable() {
    local method=$(detect_uuid_generator)
    case "$method" in
        "uuidgen")
            uuidgen | tr '[:upper:]' '[:lower:]'
            ;;
        "uuid")
            uuid -v4
            ;;
        "proc")
            cat /proc/sys/kernel/random/uuid
            ;;
        *)
            # 后备方案：使用随机数生成伪UUID
            printf '%08x-%04x-%04x-%04x-%012x\n' \
                $RANDOM$RANDOM \
                $RANDOM \
                $((RANDOM | 0x4000)) \
                $((RANDOM | 0x8000)) \
                $RANDOM$RANDOM$RANDOM
            ;;
    esac
}

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/debian_version ]]; then
            echo "debian"
        elif [[ -f /etc/redhat-release ]]; then
            echo "redhat"
        elif [[ -f /etc/alpine-release ]]; then
            echo "alpine"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# 检测包管理器
detect_package_manager() {
    if command -v apt &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v brew &> /dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# 检测网络工具
detect_network_tool() {
    if command -v ss &> /dev/null; then
        echo "ss"
    elif command -v netstat &> /dev/null; then
        echo "netstat"
    else
        return 1
    fi
}

# 检查端口占用 (跨平台)
check_port_usage_portable() {
    local port="$1"
    local tool=$(detect_network_tool)

    case "$tool" in
        "ss")
            ss -tulpn | grep -q ":$port "
            ;;
        "netstat")
            netstat -tulpn 2>/dev/null | grep -q ":$port "
            ;;
        *)
            # 无法检测，返回false (端口可用)
            return 1
            ;;
    esac
}

# 执行Docker Compose命令
run_docker_compose() {
    local compose_cmd=$(detect_docker_compose)
    if [[ $? -eq 0 ]]; then
        $compose_cmd "$@"
    else
        echo "错误: 未找到Docker Compose命令" >&2
        echo "请安装 docker-compose 或确保 'docker compose' 命令可用" >&2
        return 1
    fi
}

# 安装依赖建议
suggest_dependencies() {
    local os=$(detect_os)
    local pm=$(detect_package_manager)

    echo "检测到系统: $os"
    echo "包管理器: $pm"
    echo
    echo "建议安装以下依赖:"

    case "$pm" in
        "apt")
            echo "  sudo apt update"
            echo "  sudo apt install -y docker.io docker-compose-plugin uuid-runtime net-tools"
            ;;
        "yum"|"dnf")
            echo "  sudo $pm install -y docker docker-compose util-linux net-tools"
            ;;
        "apk")
            echo "  sudo apk add docker docker-compose util-linux net-tools"
            ;;
        "brew")
            echo "  brew install docker docker-compose"
            ;;
        *)
            echo "  请手动安装: docker, docker-compose, uuid工具, 网络工具"
            ;;
    esac
}

# 导出函数
export -f detect_docker_compose
export -f detect_uuid_generator
export -f generate_uuid_portable
export -f detect_os
export -f detect_package_manager
export -f detect_network_tool
export -f check_port_usage_portable
export -f run_docker_compose
export -f suggest_dependencies