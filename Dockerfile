# Sing-Box Docker 多阶段构建
FROM alpine:latest as downloader

# 设置工作目录
WORKDIR /tmp

# 安装依赖包
RUN apk add --no-cache \
    wget \
    tar \
    jq \
    curl

# 下载sing-box二进制文件
ARG TARGETARCH
ARG SING_BOX_VERSION=latest
RUN ARCH=$(case ${TARGETARCH} in \
    "amd64") echo "amd64" ;; \
    "arm64") echo "arm64" ;; \
    *) echo "amd64" ;; \
    esac) && \
    if [ "$SING_BOX_VERSION" = "latest" ]; then \
        VERSION=$(wget -qO- "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r '.tag_name'); \
    else \
        VERSION="$SING_BOX_VERSION"; \
    fi && \
    wget -O sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION#v}-linux-${ARCH}.tar.gz" && \
    tar -xzf sing-box.tar.gz --strip-components=1

# 运行时镜像
FROM alpine:latest

# 安装运行时依赖
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    jq \
    bash \
    && rm -rf /var/cache/apk/*

# 创建sing-box用户
RUN addgroup -g 1000 sing-box && \
    adduser -u 1000 -G sing-box -s /bin/sh -D sing-box

# 创建必要目录
RUN mkdir -p /etc/sing-box/conf \
             /var/log/sing-box \
             /opt/sing-box/bin \
             /opt/sing-box/scripts && \
    chown -R sing-box:sing-box /etc/sing-box /var/log/sing-box /opt/sing-box

# 从下载阶段复制二进制文件
COPY --from=downloader /tmp/sing-box /opt/sing-box/bin/
RUN chmod +x /opt/sing-box/bin/sing-box

# 复制配置生成脚本
COPY docker/entrypoint.sh /opt/sing-box/scripts/
COPY docker/entrypoint-multi.sh /opt/sing-box/scripts/
COPY docker/config-generator.sh /opt/sing-box/scripts/
COPY docker/multi-protocol-generator.sh /opt/sing-box/scripts/
COPY docker/config-templates/ /opt/sing-box/templates/

# 设置脚本执行权限
RUN chmod +x /opt/sing-box/scripts/*.sh && \
    chown -R sing-box:sing-box /opt/sing-box

# 暴露端口 (将通过环境变量动态配置)
EXPOSE 443 80 1080 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /opt/sing-box/bin/sing-box check -c /etc/sing-box/config.json || exit 1

# 切换到非root用户
USER sing-box

# 设置入口点
ENTRYPOINT ["/opt/sing-box/scripts/entrypoint.sh"]

# 默认命令
CMD ["run", "-c", "/etc/sing-box/config.json"]