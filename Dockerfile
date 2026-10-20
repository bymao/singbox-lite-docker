# syntax=docker/dockerfile:1
FROM alpine:3.21

# 核心和 yq 由上游 sb 菜单安装；不复制或修改上游脚本。
RUN apk add --no-cache \
        bash curl wget jq openssl tar unzip ca-certificates \
        procps socat iproute2 dcron lsof nftables iptables ip6tables \
        util-linux-misc tzdata \
    && mkdir -p /usr/local/etc/sing-box /usr/local/etc/xray

# 入口内嵌在 Dockerfile 中，仓库无需额外维护 entrypoint.sh。
RUN <<'BUILD'
cat > /entrypoint.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
umask 077

# 支持 docker compose run --rm singbox bash 等维护命令。
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

upstream="https://raw.githubusercontent.com/0xdabiaoge/singbox-lite/main"
config_dir=/usr/local/etc/sing-box
runtime_dir=/run/singboxlite
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$config_dir" /usr/local/etc/xray "$runtime_dir"
chmod 700 "$config_dir" /usr/local/etc/xray "$runtime_dir"

# 每次启动拉取上游最新版，全部通过检查后才替换本地脚本。
for script in singbox.sh advanced_relay.sh parser.sh xray_manager.sh; do
    echo "[upstream] 下载 $script"
    curl --fail --silent --show-error --location --retry 3 \
        --connect-timeout 15 --max-time 120 \
        "$upstream/$script" -o "$stage/$script"
    test -s "$stage/$script"
    head -n 1 "$stage/$script" | grep -q '^#!/bin/bash'
    bash -n "$stage/$script"
done
install -m 755 "$stage/singbox.sh" /usr/local/bin/sb
for script in advanced_relay.sh parser.sh xray_manager.sh; do
    install -m 755 "$stage/$script" "$config_dir/$script"
done
rm -rf "$stage"
trap - EXIT

cleanup() {
    trap - TERM INT
    for name in sing-box xray; do
        pid_file="$runtime_dir/$name.pid"
        if [ -s "$pid_file" ]; then
            pid=$(cat "$pid_file")
            # 仅停止对应核心，防止误用过期 PID。
            if [[ "$pid" =~ ^[0-9]+$ ]] && \
                [ "$(readlink -f "/proc/$pid/exe" 2>/dev/null)" = "/usr/local/bin/$name" ]; then
                kill "$pid" 2>/dev/null || true
            fi
        fi
    done
    kill "$cron_pid" "${sleep_pid:-}" 2>/dev/null || true
    wait || true
    exit 0
}
cron_pid=""
trap cleanup TERM INT

# 上游在没有 systemd/OpenRC 时使用 direct 模式，PID 路径与之保持一致。
# 只在容器启动时恢复服务，菜单中手动停止核心后不会被守护逻辑重新启动。
if [ -x /usr/local/bin/sing-box ] && [ -s "$config_dir/config.json" ]; then
    if [ ! -s "$config_dir/relay.json" ]; then
        echo '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}' > "$config_dir/relay.json"
    fi
    /usr/local/bin/sing-box check -c "$config_dir/config.json" -c "$config_dir/relay.json"
    /usr/local/bin/sing-box run -c "$config_dir/config.json" -c "$config_dir/relay.json" \
        >> /var/log/sing-box.log 2>&1 &
    echo $! > "$runtime_dir/sing-box.pid"
fi
if [ -x /usr/local/bin/xray ] && [ -s /usr/local/etc/xray/config.json ]; then
    /usr/local/bin/xray run -test -c /usr/local/etc/xray/config.json
    /usr/local/bin/xray run -c /usr/local/etc/xray/config.json >> /var/log/xray.log 2>&1 &
    echo $! > "$runtime_dir/xray.pid"
fi

crond -f &
cron_pid=$!
echo '[singbox] 容器已启动。运行 docker compose exec singbox sb 进入上游菜单。'
echo '[singbox] 首次使用请通过菜单 [15] 安装 sing-box，或 [16] 安装 Xray。'
while true; do
    sleep 3600 &
    sleep_pid=$!
    wait "$sleep_pid" || true
done
SCRIPT
chmod 755 /entrypoint.sh
BUILD

ENTRYPOINT ["/entrypoint.sh"]
