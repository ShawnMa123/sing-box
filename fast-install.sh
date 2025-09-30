#!/bin/bash

# Sing-Box 快速安装脚本 (优化版)
# 解决GitHub下载慢的问题，支持多镜像源

set -e

author=233boy
version=1.0.0

# 颜色定义
red='\e[31m'
yellow='\e[33m'
green='\e[92m'
blue='\e[94m'
cyan='\e[96m'
none='\e[0m'

_red() { echo -e ${red}$@${none}; }
_blue() { echo -e ${blue}$@${none}; }
_cyan() { echo -e ${cyan}$@${none}; }
_green() { echo -e ${green}$@${none}; }
_yellow() { echo -e ${yellow}$@${none}; }

is_err=$(_red "错误!")
is_warn=$(_yellow "警告!")

err() { echo -e "\n$is_err $@\n" && exit 1; }
warn() { echo -e "\n$is_warn $@\n"; }
info() { echo -e "\n$(_cyan "信息:") $@\n"; }
success() { echo -e "\n$(_green "成功:") $@\n"; }

# 系统检测
[[ $EUID != 0 ]] && err "需要 ROOT 权限运行此脚本"

# 检测包管理器
cmd=$(type -P apt-get || type -P yum || type -P dnf)
[[ ! $cmd ]] && err "不支持的系统，仅支持 Ubuntu/Debian/CentOS/RHEL"

# 检测systemd
[[ ! $(type -P systemctl) ]] && err "系统缺少 systemctl，请确保使用 systemd"

# 架构检测
case $(uname -m) in
    amd64 | x86_64) is_arch=amd64 ;;
    *aarch64* | *armv8*) is_arch=arm64 ;;
    *armv7*) is_arch=armv7 ;;
    *) err "不支持的架构: $(uname -m)" ;;
esac

# 配置变量
is_core=sing-box
is_core_name=sing-box
is_core_dir=/etc/$is_core
is_core_bin=$is_core_dir/bin/$is_core
is_conf_dir=$is_core_dir/conf
is_log_dir=/var/log/$is_core
is_sh_bin=/usr/local/bin/$is_core
is_sh_dir=$is_core_dir/sh
is_config_json=$is_core_dir/config.json
tmpdir=$(mktemp -d)

# 下载源配置 (按优先级排序)
declare -A download_sources=(
    ["github"]="https://github.com"
    ["ghproxy"]="https://ghproxy.com/https://github.com"
    ["fastgit"]="https://download.fastgit.org"
    ["gitclone"]="https://gitclone.com/github.com"
    ["jsdelivr"]="https://cdn.jsdelivr.net/gh"
)

# 镜像源优先级 (国内用户优先使用镜像)
if [[ -n "$CN_MIRROR" ]] || curl -s --connect-timeout 3 https://www.baidu.com > /dev/null 2>&1; then
    mirror_priority=("ghproxy" "gitclone" "fastgit" "jsdelivr" "github")
    info "检测到国内网络环境，优先使用镜像源"
else
    mirror_priority=("github" "ghproxy" "gitclone" "fastgit" "jsdelivr")
    info "使用国际网络环境"
fi

# 清理函数
cleanup() {
    [[ -d "$tmpdir" ]] && rm -rf "$tmpdir"
}
trap cleanup EXIT

# 检测网络工具
detect_download_tool() {
    if command -v curl &> /dev/null; then
        echo "curl"
    elif command -v wget &> /dev/null; then
        echo "wget"
    else
        return 1
    fi
}

# 下载函数 (支持多源重试)
smart_download() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local tool=$(detect_download_tool)

    [[ ! $tool ]] && err "未找到 curl 或 wget 工具"

    info "开始下载: $(basename "$output")"

    for source in "${mirror_priority[@]}"; do
        local base_url="${download_sources[$source]}"
        local download_url

        # 构造下载链接
        case "$source" in
            "jsdelivr")
                # jsdelivr CDN 特殊处理
                download_url=$(echo "$url" | sed "s|https://github.com/\([^/]*\)/\([^/]*\)/releases/download/\([^/]*\)/\(.*\)|${base_url}/\1/\2@\3/\4|")
                ;;
            "fastgit")
                download_url=$(echo "$url" | sed "s|https://github.com|${base_url}|")
                ;;
            *)
                download_url="${base_url}${url#https://github.com}"
                ;;
        esac

        echo "尝试源: $source ($download_url)"

        for ((i=1; i<=max_retries; i++)); do
            case "$tool" in
                "curl")
                    if curl -L --connect-timeout 10 --max-time 300 -# "$download_url" -o "$output"; then
                        success "下载成功: $(basename "$output")"
                        return 0
                    fi
                    ;;
                "wget")
                    if wget --timeout=10 --tries=1 --no-check-certificate "$download_url" -O "$output"; then
                        success "下载成功: $(basename "$output")"
                        return 0
                    fi
                    ;;
            esac

            [[ $i -lt $max_retries ]] && echo "重试 $i/$max_retries..."
        done

        warn "源 $source 下载失败，尝试下一个源..."
    done

    err "所有下载源均失败"
}

# 获取最新版本
get_latest_version() {
    local repo="$1"
    local api_urls=(
        "https://api.github.com/repos/$repo/releases/latest"
        "https://ghproxy.com/https://api.github.com/repos/$repo/releases/latest"
    )

    for api_url in "${api_urls[@]}"; do
        local version
        if command -v curl &> /dev/null; then
            version=$(curl -s --connect-timeout 5 "$api_url" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
        elif command -v wget &> /dev/null; then
            version=$(wget -qO- --timeout=5 "$api_url" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
        fi

        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    done

    return 1
}

# 安装依赖包
install_dependencies() {
    info "安装必要依赖..."

    local packages
    if [[ "$cmd" =~ "apt" ]]; then
        packages="curl wget tar unzip systemd"
        apt-get update -q
        apt-get install -y $packages
    elif [[ "$cmd" =~ "yum" ]]; then
        packages="curl wget tar unzip systemd"
        yum install -y $packages
    elif [[ "$cmd" =~ "dnf" ]]; then
        packages="curl wget tar unzip systemd"
        dnf install -y $packages
    fi

    success "依赖安装完成"
}

# 下载sing-box核心
download_singbox() {
    info "下载 sing-box 核心程序..."

    local version="$1"
    [[ -z "$version" ]] && {
        info "获取最新版本..."
        version=$(get_latest_version "SagerNet/sing-box")
        [[ -z "$version" ]] && err "无法获取最新版本"
        info "最新版本: $version"
    }

    local filename="${is_core}-${version#v}-linux-${is_arch}.tar.gz"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/${version}/${filename}"
    local output_file="$tmpdir/$filename"

    smart_download "$download_url" "$output_file"

    # 解压安装
    info "安装 sing-box..."
    mkdir -p "$is_core_dir/bin"
    tar -xzf "$output_file" -C "$tmpdir"
    cp "$tmpdir/${is_core}-${version#v}-linux-${is_arch}/${is_core}" "$is_core_bin"
    chmod +x "$is_core_bin"

    success "sing-box 核心安装完成"
}

# 下载管理脚本
download_scripts() {
    info "下载管理脚本..."

    local script_url="https://github.com/233boy/sing-box/releases/latest/download/code.tar.gz"
    local output_file="$tmpdir/scripts.tar.gz"

    smart_download "$script_url" "$output_file"

    # 解压安装脚本
    mkdir -p "$is_sh_dir"
    tar -xzf "$output_file" -C "$is_sh_dir"

    success "管理脚本安装完成"
}

# 下载jq工具
download_jq() {
    if command -v jq &> /dev/null; then
        info "jq 已安装，跳过下载"
        return 0
    fi

    info "下载 jq 工具..."

    local jq_url="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${is_arch}"
    local output_file="/usr/bin/jq"

    smart_download "$jq_url" "$output_file"
    chmod +x "$output_file"

    success "jq 工具安装完成"
}

# 创建systemd服务
create_systemd_service() {
    info "创建 systemd 服务..."

    cat > "/lib/systemd/system/${is_core}.service" << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=$is_core_bin run -c $is_config_json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$is_core"

    success "systemd 服务创建完成"
}

# 设置命令别名
setup_aliases() {
    info "设置命令别名..."

    # 创建管理脚本链接
    ln -sf "$is_sh_dir/${is_core}.sh" "$is_sh_bin"
    ln -sf "$is_sh_dir/${is_core}.sh" "/usr/local/bin/sb"
    chmod +x "$is_sh_bin"

    # 添加bash别名
    if ! grep -q "alias $is_core=" /root/.bashrc; then
        echo "alias $is_core=$is_sh_bin" >> /root/.bashrc
        echo "alias sb=$is_sh_bin" >> /root/.bashrc
    fi

    success "命令别名设置完成"
}

# 创建基础目录
create_directories() {
    info "创建必要目录..."

    mkdir -p "$is_core_dir"/{bin,conf} "$is_log_dir" "$is_sh_dir"

    success "目录创建完成"
}

# 获取服务器IP
get_server_ip() {
    info "获取服务器IP地址..."

    local ip_apis=(
        "https://api.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://ipinfo.io/ip"
        "https://one.one.one.one/cdn-cgi/trace"
    )

    for api in "${ip_apis[@]}"; do
        local ip
        if command -v curl &> /dev/null; then
            if [[ "$api" =~ "trace" ]]; then
                ip=$(curl -s --connect-timeout 5 "$api" | grep "ip=" | cut -d'=' -f2)
            else
                ip=$(curl -s --connect-timeout 5 "$api")
            fi
        elif command -v wget &> /dev/null; then
            if [[ "$api" =~ "trace" ]]; then
                ip=$(wget -qO- --timeout=5 "$api" | grep "ip=" | cut -d'=' -f2)
            else
                ip=$(wget -qO- --timeout=5 "$api")
            fi
        fi

        if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            export ip="$ip"
            return 0
        fi
    done

    warn "无法获取服务器IP地址"
    return 1
}

# 生成初始配置
generate_initial_config() {
    info "生成初始配置..."

    # 加载配置生成脚本
    if [[ -f "$is_sh_dir/src/core.sh" ]]; then
        cd "$is_sh_dir"
        source "$is_sh_dir/src/core.sh"

        # 生成Reality配置
        add reality 2>/dev/null || {
            warn "配置生成失败，请手动运行: $is_core"
        }
    else
        warn "未找到配置生成脚本，请手动配置"
    fi
}

# 显示安装结果
show_install_result() {
    clear
    success "sing-box 安装完成！"

    echo "=============================================="
    echo "  管理命令:"
    echo "    $is_core          # 管理面板"
    echo "    sb               # 快捷命令"
    echo "    systemctl status $is_core    # 查看状态"
    echo "    systemctl start $is_core     # 启动服务"
    echo "    systemctl stop $is_core      # 停止服务"
    echo ""
    echo "  配置文件: $is_config_json"
    echo "  日志目录: $is_log_dir"
    echo "  项目地址: https://github.com/233boy/sing-box"
    echo "=============================================="

    if [[ -n "$ip" ]]; then
        echo "  服务器IP: $ip"
        echo "=============================================="
    fi
}

# 参数处理
show_help() {
    cat << EOF
Sing-Box 快速安装脚本 (优化版) v${version}

用法: $0 [选项]

选项:
  -v, --version <版本>     指定sing-box版本 (如: v1.8.0)
  -m, --mirror             强制使用国内镜像源
  -s, --skip-deps          跳过依赖安装
  -h, --help               显示此帮助信息

示例:
  $0                       # 安装最新版本
  $0 -v v1.8.0            # 安装指定版本
  $0 -m                   # 强制使用镜像源
  $0 -s                   # 跳过依赖安装

EOF
}

# 参数解析
SING_BOX_VERSION=""
SKIP_DEPS=""
FORCE_MIRROR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            SING_BOX_VERSION="$2"
            shift 2
            ;;
        -m|--mirror)
            FORCE_MIRROR="1"
            shift
            ;;
        -s|--skip-deps)
            SKIP_DEPS="1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            err "未知参数: $1\n使用 $0 -h 查看帮助"
            ;;
    esac
done

# 强制使用镜像源
if [[ -n "$FORCE_MIRROR" ]]; then
    mirror_priority=("ghproxy" "gitclone" "fastgit" "jsdelivr" "github")
    info "强制使用镜像源"
fi

# 主安装流程
main() {
    clear
    echo "=============================================="
    echo "  Sing-Box 快速安装脚本 (优化版) v${version}"
    echo "  支持多镜像源，解决GitHub下载慢问题"
    echo "  作者: $author"
    echo "=============================================="

    # 检查是否已安装
    if [[ -f "$is_core_bin" && -f "$is_sh_bin" ]]; then
        warn "检测到已安装 sing-box"
        read -p "是否重新安装? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "安装取消"
            exit 0
        fi
    fi

    # 安装步骤
    [[ -z "$SKIP_DEPS" ]] && install_dependencies
    create_directories
    download_singbox "$SING_BOX_VERSION"
    download_scripts
    download_jq
    create_systemd_service
    setup_aliases
    get_server_ip
    generate_initial_config
    show_install_result

    success "安装完成！运行 '$is_core' 开始配置"
}

# 执行安装
main "$@"