#!/bin/bash

# Sing-Box 极速安装脚本
# 专门解决GitHub下载慢的问题

set -e

# 颜色和基础函数
red='\e[31m'; green='\e[92m'; yellow='\e[33m'; blue='\e[94m'; none='\e[0m'
_red() { echo -e ${red}$@${none}; }
_green() { echo -e ${green}$@${none}; }
_yellow() { echo -e ${yellow}$@${none}; }
_blue() { echo -e ${blue}$@${none}; }

err() { echo -e "\n$(_red "错误:") $@\n" && exit 1; }
warn() { echo -e "\n$(_yellow "警告:") $@\n"; }
info() { echo -e "\n$(_blue "信息:") $@\n"; }
success() { echo -e "\n$(_green "成功:") $@\n"; }

# 系统检测
[[ $EUID != 0 ]] && err "需要 ROOT 权限"
command -v systemctl >/dev/null || err "需要 systemd 支持"

# 架构检测
case $(uname -m) in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    armv7l) arch="armv7" ;;
    *) err "不支持的架构: $(uname -m)" ;;
esac

# 配置
core_name="sing-box"
install_dir="/usr/local/bin"
config_dir="/etc/sing-box"
log_dir="/var/log/sing-box"
service_name="sing-box"

# 最佳镜像源 (经过实际测试的快速源)
declare -a MIRRORS=(
    "https://ghproxy.com/https://github.com"
    "https://mirror.ghproxy.com/https://github.com"
    "https://ghps.cc/https://github.com"
    "https://gh.ddlc.top/https://github.com"
    "https://github.moeyy.xyz/https://github.com"
    "https://gh.con.sh/https://github.com"
    "https://cors.zme.ink/https://github.com"
    "https://hub.gitmirror.com/https://github.com"
    "https://github.com"  # 原始地址作为最后选择
)

# 快速下载函数
fast_download() {
    local file_url="$1"
    local output="$2"
    local filename=$(basename "$output")

    info "下载 $filename..."

    # 尝试每个镜像源
    for mirror in "${MIRRORS[@]}"; do
        local full_url="${mirror}${file_url#https://github.com}"

        printf "尝试: %s ... " "$(echo $mirror | cut -d'/' -f3)"

        # 使用curl下载，设置较短超时时间
        if curl -L -o "$output" --connect-timeout 8 --max-time 60 -# "$full_url" 2>/dev/null; then
            if [[ -f "$output" && -s "$output" ]]; then
                echo "成功"
                success "$filename 下载完成"
                return 0
            fi
        fi
        echo "失败"
        [[ -f "$output" ]] && rm -f "$output"
    done

    err "所有镜像源下载失败: $filename"
}

# 获取最新版本 (使用多个API)
get_latest_version() {
    local apis=(
        "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
        "https://ghproxy.com/https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    )

    for api in "${apis[@]}"; do
        local version=$(curl -s --connect-timeout 5 "$api" | grep '"tag_name"' | cut -d'"' -f4)
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    done

    # 如果API失败，使用默认版本
    echo "v1.8.10"
}

# 安装依赖
install_deps() {
    info "检查并安装依赖..."

    if command -v apt >/dev/null; then
        apt update -qq && apt install -y curl tar systemd >/dev/null 2>&1
    elif command -v yum >/dev/null; then
        yum install -y curl tar systemd >/dev/null 2>&1
    elif command -v dnf >/dev/null; then
        dnf install -y curl tar systemd >/dev/null 2>&1
    else
        warn "无法识别包管理器，请手动安装: curl tar systemd"
    fi
}

# 下载并安装sing-box
install_singbox() {
    local version="$1"
    [[ -z "$version" ]] && version=$(get_latest_version)

    info "安装 sing-box $version ..."

    # 下载
    local filename="sing-box-${version#v}-linux-${arch}.tar.gz"
    local download_url="/SagerNet/sing-box/releases/download/${version}/${filename}"
    local temp_file="/tmp/$filename"

    fast_download "https://github.com$download_url" "$temp_file"

    # 解压安装
    cd /tmp
    tar -xzf "$temp_file" >/dev/null

    local extract_dir="sing-box-${version#v}-linux-${arch}"
    if [[ ! -f "$extract_dir/sing-box" ]]; then
        err "解压失败或文件结构异常"
    fi

    # 安装二进制文件
    mkdir -p "$install_dir" "$config_dir" "$log_dir"
    cp "$extract_dir/sing-box" "$install_dir/"
    chmod +x "$install_dir/sing-box"

    # 清理临时文件
    rm -rf "$temp_file" "$extract_dir"

    success "sing-box 安装完成"
}

# 下载管理脚本
install_scripts() {
    info "安装管理脚本..."

    local script_url="/233boy/sing-box/releases/latest/download/code.tar.gz"
    local temp_file="/tmp/sing-box-scripts.tar.gz"

    fast_download "https://github.com$script_url" "$temp_file"

    # 解压到配置目录
    mkdir -p "$config_dir/scripts"
    tar -xzf "$temp_file" -C "$config_dir/scripts" >/dev/null

    # 创建管理命令
    cat > "$install_dir/sb" << 'EOF'
#!/bin/bash
exec /etc/sing-box/scripts/sing-box.sh "$@"
EOF
    chmod +x "$install_dir/sb"

    # 创建别名
    ln -sf "$install_dir/sb" "$install_dir/sing-box-manage"

    rm -f "$temp_file"
    success "管理脚本安装完成"
}

# 创建systemd服务
create_service() {
    info "创建系统服务..."

    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=$install_dir/sing-box run -c $config_dir/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$service_name" >/dev/null 2>&1

    success "系统服务创建完成"
}

# 生成示例配置
create_sample_config() {
    if [[ ! -f "$config_dir/config.json" ]]; then
        info "创建示例配置..."

        cat > "$config_dir/config.json" << 'EOF'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "listen": "127.0.0.1",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF
        success "示例配置已创建"
    fi
}

# 显示安装结果
show_result() {
    clear
    echo "========================================"
    echo "🎉 Sing-Box 极速安装完成！"
    echo "========================================"
    echo
    echo "管理命令:"
    echo "  sb                    # 快捷管理命令"
    echo "  sing-box-manage       # 完整管理命令"
    echo "  systemctl status sing-box    # 查看状态"
    echo
    echo "配置文件: $config_dir/config.json"
    echo "日志目录: $log_dir"
    echo
    echo "使用 'sb' 命令开始配置你的代理服务"
    echo "========================================"
}

# 主安装函数
main() {
    clear
    echo "========================================"
    echo "🚀 Sing-Box 极速安装脚本"
    echo "🌍 支持多镜像源，解决下载慢问题"
    echo "========================================"

    # 检查是否已安装
    if [[ -f "$install_dir/sing-box" ]]; then
        warn "检测到已安装 sing-box"
        read -p "是否重新安装? (y/N): " -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    fi

    # 执行安装步骤
    install_deps
    install_singbox "$1"
    install_scripts
    create_service
    create_sample_config
    show_result
}

# 参数处理
case "$1" in
    -h|--help)
        echo "用法: $0 [版本号]"
        echo "示例: $0 v1.8.0"
        exit 0
        ;;
    -v|--version)
        echo "Sing-Box 极速安装脚本 v1.0"
        exit 0
        ;;
    *)
        main "$1"
        ;;
esac