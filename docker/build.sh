#!/bin/bash

# Sing-Box Docker 构建脚本
# 支持多架构构建和版本管理

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 默认配置
IMAGE_NAME="sing-box"
TAG="latest"
PLATFORMS="linux/amd64,linux/arm64"
PUSH=false
BUILD_ARGS=""
SING_BOX_VERSION="latest"

# 显示帮助信息
show_help() {
    cat << EOF
Sing-Box Docker 构建脚本

用法: $0 [选项]

选项:
  -t, --tag TAG              设置镜像标签 (默认: latest)
  -n, --name NAME            设置镜像名称 (默认: sing-box)
  -p, --platforms PLATFORMS 设置构建平台 (默认: linux/amd64,linux/arm64)
  -v, --version VERSION      设置 sing-box 版本 (默认: latest)
  --push                     构建后推送到仓库
  --no-cache                 不使用缓存构建
  --pull                     构建前拉取最新基础镜像
  -h, --help                 显示此帮助信息

示例:
  $0                                    # 使用默认配置构建
  $0 -t v1.8.0 -v v1.8.0               # 构建特定版本
  $0 -p linux/amd64 --push             # 仅构建 x64 并推送
  $0 --no-cache                        # 无缓存构建

支持的平台:
  - linux/amd64   (x86_64)
  - linux/arm64   (aarch64)
  - linux/arm/v7  (armv7)

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tag)
                TAG="$2"
                shift 2
                ;;
            -n|--name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            -p|--platforms)
                PLATFORMS="$2"
                shift 2
                ;;
            -v|--version)
                SING_BOX_VERSION="$2"
                shift 2
                ;;
            --push)
                PUSH=true
                shift
                ;;
            --no-cache)
                BUILD_ARGS="$BUILD_ARGS --no-cache"
                shift
                ;;
            --pull)
                BUILD_ARGS="$BUILD_ARGS --pull"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查依赖
check_dependencies() {
    local deps=("docker" "jq")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "依赖 $dep 未安装"
            exit 1
        fi
    done

    # 检查 buildx
    if ! docker buildx version &> /dev/null; then
        log_error "Docker Buildx 未安装或未启用"
        log_info "请运行: docker buildx install"
        exit 1
    fi
}

# 获取最新版本
get_latest_version() {
    if [[ "$SING_BOX_VERSION" == "latest" ]]; then
        log_info "获取 sing-box 最新版本..."
        SING_BOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
        log_info "最新版本: $SING_BOX_VERSION"
    fi
}

# 创建 buildx builder
setup_builder() {
    local builder_name="singbox-builder"

    if ! docker buildx inspect "$builder_name" &> /dev/null; then
        log_info "创建多架构构建器..."
        docker buildx create --name "$builder_name" --driver docker-container --use
        docker buildx inspect --bootstrap
    else
        log_info "使用现有构建器: $builder_name"
        docker buildx use "$builder_name"
    fi
}

# 构建镜像
build_image() {
    local full_image_name="$IMAGE_NAME:$TAG"
    local build_cmd="docker buildx build"

    # 基础参数
    build_cmd="$build_cmd --platform $PLATFORMS"
    build_cmd="$build_cmd --build-arg SING_BOX_VERSION=$SING_BOX_VERSION"
    build_cmd="$build_cmd -t $full_image_name"

    # 添加额外的构建参数
    if [[ -n "$BUILD_ARGS" ]]; then
        build_cmd="$build_cmd $BUILD_ARGS"
    fi

    # 是否推送
    if [[ "$PUSH" == "true" ]]; then
        build_cmd="$build_cmd --push"
        log_info "构建并推送镜像: $full_image_name"
    else
        build_cmd="$build_cmd --load"
        log_info "构建镜像: $full_image_name"
    fi

    # 添加构建上下文
    build_cmd="$build_cmd ."

    log_info "执行构建命令: $build_cmd"
    log_info "平台: $PLATFORMS"
    log_info "Sing-Box 版本: $SING_BOX_VERSION"

    # 执行构建
    eval "$build_cmd"
}

# 构建后验证
verify_build() {
    if [[ "$PUSH" != "true" ]]; then
        local full_image_name="$IMAGE_NAME:$TAG"

        log_info "验证构建的镜像..."

        # 检查镜像是否存在
        if docker images | grep -q "$IMAGE_NAME.*$TAG"; then
            log_success "镜像构建成功: $full_image_name"

            # 显示镜像信息
            log_info "镜像信息:"
            docker images | grep "$IMAGE_NAME.*$TAG"

            # 快速测试
            log_info "测试镜像..."
            if docker run --rm "$full_image_name" version; then
                log_success "镜像测试通过"
            else
                log_warn "镜像测试失败，但构建完成"
            fi
        else
            log_error "镜像构建失败"
            exit 1
        fi
    else
        log_success "镜像已推送到仓库"
    fi
}

# 清理构建器
cleanup() {
    if [[ "${CLEANUP_BUILDER:-false}" == "true" ]]; then
        log_info "清理构建器..."
        docker buildx rm singbox-builder 2>/dev/null || true
    fi
}

# 显示使用说明
show_usage() {
    local full_image_name="$IMAGE_NAME:$TAG"

    cat << EOF

🎉 构建完成！

使用示例:

1. 直接运行 (VLESS Reality):
   docker run -d \\
     --name singbox \\
     -p 443:443 \\
     -e PROTOCOL=vless-reality \\
     -e PORT=443 \\
     -e UUID=\$(uuidgen) \\
     -e SERVER_NAME=www.cloudflare.com \\
     $full_image_name

2. 使用 docker-compose:
   docker-compose --profile vless-reality up -d

3. 自定义配置:
   docker run -d \\
     --name singbox-custom \\
     -p 8080:8080 \\
     -v ./config.json:/etc/sing-box/config.json:ro \\
     $full_image_name

4. 查看版本:
   docker run --rm $full_image_name version

更多信息请查看: docker/README.md

EOF
}

# 主函数
main() {
    log_info "开始构建 Sing-Box Docker 镜像..."

    # 解析参数
    parse_args "$@"

    # 检查依赖
    check_dependencies

    # 获取版本信息
    get_latest_version

    # 设置构建器
    setup_builder

    # 设置清理陷阱
    trap cleanup EXIT

    # 执行构建
    build_image

    # 验证构建
    verify_build

    # 显示使用说明
    show_usage

    log_success "构建流程完成！"
}

# 执行主函数
main "$@"