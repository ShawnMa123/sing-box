#!/bin/bash

# Sing-Box 镜像源配置文件
# 提供各种GitHub镜像和加速服务

# 镜像源配置
declare -A MIRROR_SOURCES=(
    # GitHub官方
    ["github"]="https://github.com"

    # 国内镜像服务
    ["ghproxy"]="https://ghproxy.com/https://github.com"
    ["gitclone"]="https://gitclone.com/github.com"
    ["fastgit"]="https://download.fastgit.org"

    # CDN服务
    ["jsdelivr"]="https://cdn.jsdelivr.net/gh"
    ["statically"]="https://cdn.statically.io/gh"

    # 其他镜像
    ["hub_fastgit"]="https://hub.fastgit.xyz"
    ["kkgithub"]="https://kkgithub.com"
    ["gitee_mirror"]="https://gitee.com/mirrors"
)

# API接口镜像
declare -A API_MIRRORS=(
    ["github_api"]="https://api.github.com"
    ["ghproxy_api"]="https://ghproxy.com/https://api.github.com"
    ["fastgit_api"]="https://api.fastgit.org"
)

# 检测最佳镜像源
detect_best_mirror() {
    local test_urls=(
        "https://github.com"
        "https://ghproxy.com/https://github.com"
        "https://gitclone.com/github.com"
        "https://download.fastgit.org"
    )

    local best_mirror=""
    local best_time=9999

    echo "正在检测最佳镜像源..."

    for url in "${test_urls[@]}"; do
        local start_time=$(date +%s%N)

        if curl -s --connect-timeout 5 --max-time 10 "${url}/SagerNet/sing-box" > /dev/null 2>&1; then
            local end_time=$(date +%s%N)
            local response_time=$(( (end_time - start_time) / 1000000 )) # 转换为毫秒

            echo "  ${url}: ${response_time}ms"

            if [[ $response_time -lt $best_time ]]; then
                best_time=$response_time
                best_mirror="$url"
            fi
        else
            echo "  ${url}: 超时"
        fi
    done

    if [[ -n "$best_mirror" ]]; then
        echo "最佳镜像源: $best_mirror (${best_time}ms)"
        echo "$best_mirror"
    else
        echo "所有镜像源均无法连接，使用GitHub官方"
        echo "https://github.com"
    fi
}

# 根据地区选择镜像源优先级
get_mirror_priority() {
    # 检测是否为中国大陆用户
    if curl -s --connect-timeout 3 https://www.baidu.com > /dev/null 2>&1; then
        # 国内用户优先级
        echo "ghproxy gitclone fastgit kkgithub jsdelivr github"
    else
        # 国外用户优先级
        echo "github jsdelivr ghproxy gitclone fastgit"
    fi
}

# 构造下载链接
build_download_url() {
    local base_url="$1"
    local github_url="$2"

    case "$base_url" in
        *"jsdelivr"*)
            # jsdelivr CDN 特殊处理: /user/repo@tag/file
            echo "$github_url" | sed "s|https://github.com/\([^/]*\)/\([^/]*\)/releases/download/\([^/]*\)/\(.*\)|${base_url}/\1/\2@\3/\4|"
            ;;
        *"statically"*)
            # statically CDN 特殊处理
            echo "$github_url" | sed "s|https://github.com/\([^/]*\)/\([^/]*\)/releases/download/\([^/]*\)/\(.*\)|${base_url}/\1/\2/\3/\4|"
            ;;
        *"fastgit"*)
            echo "$github_url" | sed "s|https://github.com|${base_url}|"
            ;;
        *"gitee"*)
            # Gitee镜像特殊处理
            echo "$github_url" | sed "s|https://github.com/\([^/]*\)/\([^/]*\)|${base_url}/\1/\2|"
            ;;
        *)
            # 一般镜像处理
            echo "${base_url}${github_url#https://github.com}"
            ;;
    esac
}

# 测试下载速度
test_download_speed() {
    local url="$1"
    local size_limit="1M" # 测试下载1MB

    local start_time=$(date +%s%N)

    if curl -r 0-1048576 -s --connect-timeout 5 --max-time 30 "$url" > /dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 )) # 毫秒

        if [[ $duration -gt 0 ]]; then
            local speed=$(( 1048576 * 1000 / duration )) # 字节/秒
            local speed_mb=$(( speed / 1048576 )) # MB/s
            echo "${speed_mb}"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# 选择最快的下载源
select_fastest_source() {
    local github_url="$1"
    local priority_list=($(get_mirror_priority))

    echo "测试各镜像源下载速度..."

    local best_url=""
    local best_speed=0

    for source in "${priority_list[@]}"; do
        if [[ -n "${MIRROR_SOURCES[$source]}" ]]; then
            local base_url="${MIRROR_SOURCES[$source]}"
            local test_url=$(build_download_url "$base_url" "$github_url")

            echo -n "测试 $source: "
            local speed=$(test_download_speed "$test_url")

            if [[ $speed -gt 0 ]]; then
                echo "${speed} MB/s"
                if [[ $speed -gt $best_speed ]]; then
                    best_speed=$speed
                    best_url="$test_url"
                fi
            else
                echo "失败"
            fi
        fi
    done

    if [[ -n "$best_url" ]]; then
        echo "选择最快源: $best_url (${best_speed} MB/s)"
        echo "$best_url"
    else
        echo "所有源均失败，使用原始链接"
        echo "$github_url"
    fi
}

# 导出函数供其他脚本使用
export -f detect_best_mirror
export -f get_mirror_priority
export -f build_download_url
export -f test_download_speed
export -f select_fastest_source