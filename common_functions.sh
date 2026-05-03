#!/system/bin/sh
# common_functions.sh — KernelSU MiTun Module
# Core utility function library. Source this file from other scripts.
# Do NOT execute directly.
#
# Usage: . "$(dirname "$0")/common_functions.sh"

DATA_DIR="/data/adb/mitun"
BIN_PATH="$DATA_DIR/mihomo"
CONFIG_PATH="$DATA_DIR/config.yaml"
PID_FILE="$DATA_DIR/run/mihomo.pid"
LOG_FILE="$DATA_DIR/run/mihomo.log"
TUN_DEVICE="mihomo"
API_HOST="127.0.0.1"
API_PORT="9090"
API_SECRET=""

# _log_msg LEVEL message
_log_msg() {
    _level="$1"
    shift
    _msg="$*"
    _ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '0000-00-00 00:00:00')"
    _line="[$_ts] [$_level] $_msg"

    if [ -n "$LOG_FILE" ]; then
        _log_dir="$(dirname "$LOG_FILE")"
        [ -d "$_log_dir" ] || mkdir -p "$_log_dir" 2>/dev/null
        printf '%s\n' "$_line" >> "$LOG_FILE" 2>/dev/null
    fi

    log -t MiTun "$_line" 2>/dev/null || true
}

log_info() {
    _log_msg "INFO" "$@"
}

log_error() {
    _log_msg "ERROR" "$@"
}

# read_pid — prints the PID stored in PID_FILE, or empty string
read_pid() {
    if [ ! -f "$PID_FILE" ]; then
        printf ''
        return 0
    fi
    _pid="$(cat "$PID_FILE" 2>/dev/null)"
    _pid="$(printf '%s' "$_pid" | tr -d '[:space:]')"
    printf '%s' "$_pid"
}

# is_running — returns 0 if mihomo process is alive, 1 otherwise
# Side-effect: removes stale PID_FILE when process is dead
is_running() {
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi

    _pid="$(read_pid)"

    if [ -z "$_pid" ] || [ "$_pid" -le 0 ] 2>/dev/null; then
        rm -f "$PID_FILE" 2>/dev/null
        return 1
    fi

    if [ -d "/proc/$_pid" ]; then
        return 0
    else
        rm -f "$PID_FILE" 2>/dev/null
        return 1
    fi
}

# wait_for_tun DEVICE TIMEOUT
# Returns 0 on success, 1 on timeout
wait_for_tun() {
    _device="$1"
    _timeout="$2"
    _elapsed=0

    while [ "$_elapsed" -lt "$_timeout" ]; do
        if ip link show "$_device" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        _elapsed=$((_elapsed + 1))
    done

    return 1
}


# start_mihomo — starts mihomo in the background
# Idempotent: if already running, logs current PID and returns 0
start_mihomo() {
    if is_running; then
        _cur_pid="$(read_pid)"
        log_info "mihomo already running, pid=$_cur_pid"
        return 0
    fi

    if [ ! -x "$BIN_PATH" ]; then
        log_error "mihomo binary not found or not executable: $BIN_PATH"
        return 1
    fi

    if [ ! -f "$CONFIG_PATH" ]; then
        log_error "config.yaml not found: $CONFIG_PATH"
        return 1
    fi

    if [ ! -d "$DATA_DIR/run" ]; then
        log_error "run directory not found: $DATA_DIR/run"
        return 1
    fi

    nohup setsid "$BIN_PATH" -d "$DATA_DIR" >> "$LOG_FILE" 2>&1 &
    _new_pid=$!

    printf '%s\n' "$_new_pid" > "$PID_FILE"

    log_info "mihomo started, pid=$_new_pid"

    if ! wait_for_tun "$TUN_DEVICE" 10; then
        log_error "TUN interface '$TUN_DEVICE' did not come up within 10s"
        stop_mihomo
        return 1
    fi

    log_info "TUN interface '$TUN_DEVICE' is up"
    return 0
}

# stop_mihomo — stops mihomo gracefully
# Idempotent: returns 0 even if mihomo is not running
stop_mihomo() {
    _pid="$(read_pid)"

    if [ -z "$_pid" ] || ! [ -d "/proc/$_pid" ] 2>/dev/null; then
        rm -f "$PID_FILE" 2>/dev/null
        log_info "mihomo not running (stop_mihomo: no-op)"
        return 0
    fi

    kill -TERM "$_pid" 2>/dev/null
    _waited=0
    while [ "$_waited" -lt 5 ]; do
        if ! [ -d "/proc/$_pid" ] 2>/dev/null; then
            break
        fi
        sleep 1
        _waited=$((_waited + 1))
    done

    if [ -d "/proc/$_pid" ] 2>/dev/null; then
        log_info "mihomo did not exit after SIGTERM, sending SIGKILL (pid=$_pid)"
        kill -KILL "$_pid" 2>/dev/null
        sleep 1
    fi

    rm -f "$PID_FILE" 2>/dev/null
    log_info "mihomo stopped (pid=$_pid)"
    return 0
}

# ensure_tun_device — creates /dev/net/tun if it does not exist
ensure_tun_device() {
    if [ ! -e "/dev/net/tun" ]; then
        log_info "ensure_tun_device: /dev/net/tun not found — creating device node"
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200
        chmod 666 /dev/net/tun
        log_info "ensure_tun_device: /dev/net/tun created (major=10, minor=200, mode=0666)"
    fi
}

# handle_startup_failure REASON
# Cleans up half-initialized state and logs troubleshooting hints
handle_startup_failure() {
    _reason="$1"

    log_error "Startup failed: $_reason"

    _pid="$(read_pid)"
    if [ -n "$_pid" ] && [ -d "/proc/$_pid" ] 2>/dev/null; then
        log_error "Killing residual mihomo process (pid=$_pid)"
        kill -KILL "$_pid" 2>/dev/null
    fi

    rm -f "$PID_FILE" 2>/dev/null

    if ip link show "$TUN_DEVICE" >/dev/null 2>&1; then
        log_error "Removing residual TUN interface: $TUN_DEVICE"
        ip link delete "$TUN_DEVICE" 2>/dev/null || true
    fi

    log_error "--- Troubleshooting hints ---"
    log_error "  1. config.yaml syntax error — run: $BIN_PATH -t -d $DATA_DIR"
    log_error "  2. Proxy server unreachable — check proxy node connectivity"
    log_error "  3. TUN kernel module not loaded — check: ls /dev/net/tun"
    log_error "  4. SELinux blocking TUN creation — check: dmesg | grep avc"
    log_error "Check full log: $LOG_FILE"
}
