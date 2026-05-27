#!/bin/sh
set -e

SINGBOX_BIN="/usr/local/bin/sing-box"
SINGBOX_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="${SINGBOX_DIR}/config.json"
RELAY_JSON="${SINGBOX_DIR}/relay.json"
PID_FILE="/tmp/sing-box.pid"
LOG_FILE="/var/log/sing-box.log"

# 启动 sing-box（如果配置存在且有节点）
start_singbox() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[singbox] 配置文件不存在，跳过启动（请进入容器执行 sb 进行配置）"
        return
    fi

    # 确保 relay.json 存在
    [ -f "$RELAY_JSON" ] || echo '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}' > "$RELAY_JSON"

    # 停止旧进程
    if [ -f "$PID_FILE" ]; then
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi

    echo "[singbox] 启动 sing-box..."
    ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true \
    ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM=true \
    ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true \
    nohup "$SINGBOX_BIN" run -c "$CONFIG_FILE" -c "$RELAY_JSON" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "[singbox] sing-box 已启动 (PID: $!)"
}

# 进程守护：若进程意外退出则自动重启
watchdog() {
    while true; do
        sleep 30

        # 检测 sing-box
        if [ -f "$CONFIG_FILE" ] && [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                echo "[watchdog] sing-box 进程已退出，正在重启..."
                start_singbox
            fi
        fi
    done
}

# 信号处理：优雅关闭
cleanup() {
    echo "容器正在停止..."
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup TERM INT

echo "=============================================="
echo "  sing-box Docker 容器启动"
echo "  使用 'docker exec -it <容器名> sb' 进行配置"
echo "=============================================="

# 确保配置目录存在
mkdir -p "$SINGBOX_DIR"

start_singbox

echo ""
echo "容器运行中，可通过以下命令进入配置："
echo "  docker exec -it <容器名> sb"
echo ""

# 启动守护并保持容器运行
watchdog
