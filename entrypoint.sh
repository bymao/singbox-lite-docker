#!/bin/sh
set -e

SINGBOX_BIN="/usr/local/bin/sing-box"
SINGBOX_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="${SINGBOX_DIR}/config.json"
RELAY_JSON="${SINGBOX_DIR}/relay.json"
PID_FILE="/tmp/sing-box.pid"
LOG_FILE="/var/log/sing-box.log"

XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/usr/local/etc/xray"
XRAY_CONFIG="${XRAY_DIR}/config.json"
XRAY_PID="/tmp/xray.pid"
XRAY_LOG="/var/log/xray.log"

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

# 启动 xray（如果配置存在且有节点）
start_xray() {
    if [ ! -f "$XRAY_CONFIG" ]; then
        echo "[xray] 配置文件不存在，跳过启动"
        return
    fi

    # 检查是否有配置的 inbounds
    inbound_count=$(jq '.inbounds | length' "$XRAY_CONFIG" 2>/dev/null)
    inbound_count=${inbound_count:-0}
    if [ "$inbound_count" -eq 0 ]; then
        echo "[xray] 暂无节点配置，跳过启动"
        return
    fi

    # 停止旧进程
    if [ -f "$XRAY_PID" ]; then
        old_pid=$(cat "$XRAY_PID" 2>/dev/null)
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null || true
        rm -f "$XRAY_PID"
    fi

    echo "[xray] 启动 xray..."
    nohup "$XRAY_BIN" run -c "$XRAY_CONFIG" >> "$XRAY_LOG" 2>&1 &
    echo $! > "$XRAY_PID"
    echo "[xray] xray 已启动 (PID: $!)"
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

        # 检测 xray
        if [ -f "$XRAY_CONFIG" ] && [ -f "$XRAY_PID" ]; then
            pid=$(cat "$XRAY_PID" 2>/dev/null)
            if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                echo "[watchdog] xray 进程已退出，正在重启..."
                start_xray
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
    if [ -f "$XRAY_PID" ]; then
        kill "$(cat "$XRAY_PID" 2>/dev/null)" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup TERM INT

echo "=============================================="
echo "  sing-box & Xray Docker 容器启动"
echo "  使用 'docker exec -it <容器名> sb' 进行配置"
echo "=============================================="

# 确保配置目录存在
mkdir -p "$SINGBOX_DIR" "$XRAY_DIR"

start_singbox
start_xray

echo ""
echo "容器运行中，可通过以下命令进入配置："
echo "  docker exec -it <容器名> sb"
echo ""

# 启动守护并保持容器运行
watchdog
