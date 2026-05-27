FROM alpine:3.21

# 安装系统依赖
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    jq \
    openssl \
    tar \
    unzip \
    ca-certificates \
    procps \
    socat \
    iproute2 \
    dcron \
    lsof \
    iptables \
    ip6tables \
    tzdata \
    && update-ca-certificates

# 安装 yq（YAML 处理工具，脚本依赖）
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64|amd64)   YQ_ARCH="amd64" ;; \
        aarch64|arm64)  YQ_ARCH="arm64" ;; \
        armv7l)         YQ_ARCH="arm" ;; \
        *)              YQ_ARCH="amd64" ;; \
    esac && \
    wget -qO /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}" && \
    chmod +x /usr/local/bin/yq

# 安装 sing-box（musl 版，适配 Alpine）
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64|amd64)   SB_ARCH="amd64" ;; \
        aarch64|arm64)  SB_ARCH="arm64" ;; \
        armv7l)         SB_ARCH="armv7" ;; \
        *)              SB_ARCH="amd64" ;; \
    esac && \
    SEARCH="${SB_ARCH}-musl.tar.gz" && \
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | jq -r ".assets[] | select(.name | contains(\"${SEARCH}\")) | .browser_download_url" \
        | head -1) && \
    wget -qO /tmp/sing-box.tar.gz "$DOWNLOAD_URL" && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv $(find /tmp -name sing-box -type f | head -1) /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -f /tmp/sing-box.tar.gz

# 复制脚本到镜像
COPY singbox.sh /usr/local/bin/sb
COPY xray_manager.sh /usr/local/etc/sing-box/xray_manager.sh
COPY advanced_relay.sh /usr/local/etc/sing-box/advanced_relay.sh
COPY parser.sh /usr/local/etc/sing-box/parser.sh
RUN chmod +x /usr/local/bin/sb \
    /usr/local/etc/sing-box/xray_manager.sh \
    /usr/local/etc/sing-box/advanced_relay.sh \
    /usr/local/etc/sing-box/parser.sh

# 创建配置目录并写入依赖安装状态（避免容器内重复安装依赖）
RUN mkdir -p /usr/local/etc/sing-box && \
    echo "20260524-2" > /usr/local/etc/sing-box/dependencies.ok

# 复制入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 配置目录声明（供 docker-compose volume 挂载）
VOLUME ["/usr/local/etc/sing-box"]

ENTRYPOINT ["/entrypoint.sh"]
