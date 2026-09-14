#!/system/bin/sh
# common_functions.sh — MiTun shared utilities. Source only; do not execute.
#
# Usage: . "$(dirname "$0")/common_functions.sh"

DATA_DIR="/data/adb/mitun"
RUN_DIR="$DATA_DIR/run"
PID_FILE="$RUN_DIR/mitun.pid"
LEGACY_PID_FILE="$RUN_DIR/mihomo.pid"
LOG_FILE="$RUN_DIR/mitun.log"
CORE_LOG="$RUN_DIR/core.log"

MIHOMO_BIN="$DATA_DIR/mihomo"
MIHOMO_CONFIG="$DATA_DIR/config.yaml"
SING_BOX_BIN="$DATA_DIR/sing-box"
SING_BOX_CONFIG="$DATA_DIR/config.json"

CORE_NAME=""
BIN_PATH=""
CONFIG_PATH=""
TUN_DEVICE=""

MIHOMO_TUN_DEVICE="mihomo"
SING_BOX_TUN_DEVICE="sing-box"

# Log rotation threshold, in KiB.
LOG_MAX_KB="${LOG_MAX_KB:-1024}"

# ----- logging ---------------------------------------------------------------

ensure_run_dir() {
    mkdir -p "$RUN_DIR" || return 1
    chown 0:0 "$RUN_DIR" || return 1
    chmod 0700 "$RUN_DIR" || return 1
}

_mitun_log() {
    _lvl="$1"; shift
    _ts="$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null)"
    _line="[$_ts] [$_lvl] $*"
    if ensure_run_dir 2>/dev/null; then
        printf '%s\n' "$_line" >>"$LOG_FILE" 2>/dev/null
    fi
    log -t MiTun "$_line" 2>/dev/null || true
}

log_info()  { _mitun_log INFO  "$@"; }
log_error() { _mitun_log ERROR "$@"; }

# Rotate $1 when its size exceeds ${2:-$LOG_MAX_KB} KiB. Single .1 backup.
rotate_log_if_big() {
    _file="$1"; _max_kb="${2:-$LOG_MAX_KB}"
    [ -f "$_file" ] || return 0
    _bytes="$(wc -c <"$_file" 2>/dev/null | tr -d ' ')"
    [ -n "$_bytes" ] || return 0
    if [ "$_bytes" -gt $((_max_kb * 1024)) ] 2>/dev/null; then
        mv -f "$_file" "${_file}.1" 2>/dev/null || true
    fi
}

# ----- locks -----------------------------------------------------------------

# try_lock <lock_dir> — non-blocking. Acquires an atomic directory lock,
# reclaiming it first if the recorded holder PID is dead.
# Returns 0 on success, 1 if another live holder owns the lock.
try_lock() {
    _lock="$1"
    if [ -d "$_lock" ]; then
        _lp="$(tr -d '[:space:]' <"$_lock/pid" 2>/dev/null)"
        if [ -z "$_lp" ] || [ ! -d "/proc/$_lp" ]; then
            rm -rf "$_lock" 2>/dev/null
        fi
    fi
    mkdir "$_lock" 2>/dev/null || return 1
    if ! printf '%s\n' "$$" >"$_lock/pid" 2>/dev/null; then
        rm -rf "$_lock" 2>/dev/null
        return 1
    fi
    return 0
}

release_lock() { rm -rf "$1" 2>/dev/null; }

# ----- pid / process ---------------------------------------------------------

detect_core() {
    if [ -x "$MIHOMO_BIN" ] && [ -f "$MIHOMO_CONFIG" ]; then
        CORE_NAME="mihomo"
        BIN_PATH="$MIHOMO_BIN"
        CONFIG_PATH="$MIHOMO_CONFIG"
        TUN_DEVICE="$MIHOMO_TUN_DEVICE"
        return 0
    fi

    if [ -x "$SING_BOX_BIN" ] && [ -f "$SING_BOX_CONFIG" ]; then
        CORE_NAME="sing-box"
        BIN_PATH="$SING_BOX_BIN"
        CONFIG_PATH="$SING_BOX_CONFIG"
        TUN_DEVICE="$SING_BOX_TUN_DEVICE"
        return 0
    fi

    CORE_NAME=""
    BIN_PATH=""
    CONFIG_PATH=""
    TUN_DEVICE=""
    return 1
}

core_log_path() {
    [ -n "$CORE_NAME" ] && printf '%s/%s.log\n' "$RUN_DIR" "$CORE_NAME" && return 0
    printf '%s\n' "$CORE_LOG"
}

read_pid() {
    if [ -f "$PID_FILE" ]; then
        tr -d '[:space:]' <"$PID_FILE" 2>/dev/null
        return 0
    fi
    [ -f "$LEGACY_PID_FILE" ] || return 0
    tr -d '[:space:]' <"$LEGACY_PID_FILE" 2>/dev/null
}

_is_core_pid() {
    _p="$1"
    if [ -n "$_p" ] && [ "$_p" -gt 0 ] 2>/dev/null && [ -r "/proc/$_p/exe" ]; then
        _exe="$(readlink "/proc/$_p/exe" 2>/dev/null)"
        [ "$_exe" = "$MIHOMO_BIN" ] && return 0
        [ "$_exe" = "$MIHOMO_BIN (deleted)" ] && return 0
        [ "$_exe" = "$SING_BOX_BIN" ] && return 0
        [ "$_exe" = "$SING_BOX_BIN (deleted)" ] && return 0
    fi
    return 1
}

# PID 对应进程必须由 MiTun 的完整二进制路径启动；不匹配时清理陈旧 PID 文件。
is_running() {
    _p="$(read_pid)"
    _is_core_pid "$_p" && return 0
    rm -f "$PID_FILE" "$LEGACY_PID_FILE" 2>/dev/null
    return 1
}

# ----- tun -------------------------------------------------------------------

wait_for_tun() {
    _dev="$1"; _timeout="${2:-10}"; _waited=0
    while [ "$_waited" -lt "$_timeout" ]; do
        ip link show "$_dev" >/dev/null 2>&1 && return 0
        sleep 1
        _waited=$((_waited + 1))
    done
    return 1
}

# Probe /dev/net/tun. We deliberately do NOT mknod: on modern Android the
# node is created by ueventd when the kernel driver is present; creating a
# bogus node when the driver is absent only defers the failure.
ensure_tun_device() {
    if [ -c /dev/net/tun ]; then
        return 0
    fi
    log_error "/dev/net/tun not present — kernel TUN driver may be missing"
    return 1
}

_cleanup_tun() {
    [ -n "$TUN_DEVICE" ] || return 0
    if ip link show "$TUN_DEVICE" >/dev/null 2>&1; then
        ip link delete "$TUN_DEVICE" 2>/dev/null || true
    fi
}

# ----- lifecycle -------------------------------------------------------------

_wait_for_process_exit() {
    _p="$1"; _timeout="$2"; _waited=0
    while [ "$_waited" -lt "$_timeout" ] && _is_core_pid "$_p"; do
        sleep 1
        _waited=$((_waited + 1))
    done
    ! _is_core_pid "$_p"
}

_stop_pid() {
    _p="$1"
    _is_core_pid "$_p" || return 0

    if ! kill -TERM "$_p" 2>/dev/null && _is_core_pid "$_p"; then
        log_error "failed to send TERM, pid=$_p"
        return 1
    fi
    _wait_for_process_exit "$_p" 5 && return 0

    if ! kill -KILL "$_p" 2>/dev/null && _is_core_pid "$_p"; then
        log_error "failed to send KILL, pid=$_p"
        return 1
    fi
    if ! _wait_for_process_exit "$_p" 5; then
        log_error "process did not exit after KILL, pid=$_p"
        return 1
    fi
    return 0
}

protect_process() {
    _p="$1"
    _is_core_pid "$_p" || return 0

    _ok=1
    if echo -1000 >"/proc/$_p/oom_score_adj" 2>/dev/null; then
        _ok=0
    fi
    renice -20 "$_p" >/dev/null 2>&1 || true

    if [ "$_ok" -eq 0 ]; then
        log_info "protected process, pid=$_p"
    else
        log_error "failed to set oom_score_adj, pid=$_p"
    fi
}

# 生命周期锁串行化启动、停止和 Action 状态切换，最多等待 60 秒。
_acquire_lifecycle_lock() {
    ensure_run_dir || return 1
    _lock="$RUN_DIR/lifecycle.lock"
    _tries=0
    while [ "$_tries" -lt 60 ]; do
        try_lock "$_lock" && return 0
        sleep 1
        _tries=$((_tries + 1))
    done
    return 1
}

_release_lifecycle_lock() { release_lock "$RUN_DIR/lifecycle.lock"; }

_write_pid() {
    _pid="$1"
    _pid_tmp="$PID_FILE.$$"
    if ! printf '%s\n' "$_pid" >"$_pid_tmp" ||
       ! chmod 0600 "$_pid_tmp" ||
       ! mv -f "$_pid_tmp" "$PID_FILE"; then
        rm -f "$_pid_tmp" 2>/dev/null
        return 1
    fi
    return 0
}

# 已运行时直接成功返回。
start_core() {
    if ! _acquire_lifecycle_lock; then
        log_error "failed to acquire lifecycle lock while starting"
        return 1
    fi

    _do_start_core
    _rc=$?
    _release_lifecycle_lock
    return "$_rc"
}

_do_start_core() {
    # Re-check under lock — a concurrent caller may have won the race.
    if is_running; then
        log_info "already running, pid=$(read_pid)"
        return 0
    fi

    if ! detect_core; then
        log_error "no supported core found; need mihomo+config.yaml or sing-box+config.json under $DATA_DIR"
        return 1
    fi

    ensure_tun_device || return 1

    CORE_LOG="$(core_log_path)"
    rotate_log_if_big "$CORE_LOG"
    rotate_log_if_big "$LOG_FILE"

    # Stale TUN from a crashed previous run
    _cleanup_tun

    # nohup only (no setsid) so $! is guaranteed to be the core process PID.
    if [ "$CORE_NAME" = "mihomo" ]; then
        nohup "$BIN_PATH" -d "$DATA_DIR" >>"$CORE_LOG" 2>&1 &
    else
        nohup "$BIN_PATH" run -c "$CONFIG_PATH" >>"$CORE_LOG" 2>&1 &
    fi
    _pid=$!

    sleep 1
    if ! _is_core_pid "$_pid"; then
        log_error "$CORE_NAME exited immediately — check $CORE_LOG"
        return 1
    fi

    protect_process "$_pid"
    if ! _write_pid "$_pid"; then
        log_error "failed to write PID file $PID_FILE"
        if ! _stop_pid "$_pid"; then
            log_error "failed to stop untracked $CORE_NAME process, pid=$_pid"
            return 1
        fi
        _cleanup_tun
        return 1
    fi
    rm -f "$LEGACY_PID_FILE" 2>/dev/null
    log_info "started $CORE_NAME, pid=$_pid"

    if [ -n "$TUN_DEVICE" ] && ! wait_for_tun "$TUN_DEVICE" 10; then
        log_error "TUN '$TUN_DEVICE' did not appear within 10s"
        if ! _stop_pid "$_pid"; then
            log_error "failed to stop $CORE_NAME after startup timeout, pid=$_pid"
            return 1
        fi
        rm -f "$PID_FILE" "$LEGACY_PID_FILE" 2>/dev/null
        _cleanup_tun
        return 1
    fi

    if ! _is_core_pid "$_pid"; then
        log_error "$CORE_NAME exited during startup — check $CORE_LOG"
        rm -f "$PID_FILE" "$LEGACY_PID_FILE" 2>/dev/null
        _cleanup_tun
        return 1
    fi

    [ -n "$TUN_DEVICE" ] && log_info "TUN '$TUN_DEVICE' is up"
    return 0
}

# 未运行时直接成功返回；确认进程退出后才清理 TUN。
stop_core() {
    if ! _acquire_lifecycle_lock; then
        log_error "failed to acquire lifecycle lock while stopping"
        return 1
    fi

    _do_stop_core
    _rc=$?
    _release_lifecycle_lock
    return "$_rc"
}

_do_stop_core() {
    detect_core >/dev/null 2>&1 || true
    if ! is_running; then
        _cleanup_tun
        return 0
    fi
    _p="$(read_pid)"
    if ! _stop_pid "$_p"; then
        log_error "failed to stop core, pid=$_p"
        return 1
    fi
    rm -f "$PID_FILE" "$LEGACY_PID_FILE" 2>/dev/null
    _cleanup_tun
    log_info "stopped, pid=$_p"
    return 0
}

# Compatibility wrappers for existing entry scripts and older user hooks.
start_mihomo() { start_core "$@"; }
stop_mihomo() { stop_core "$@"; }
