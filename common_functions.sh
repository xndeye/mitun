#!/system/bin/sh
# common_functions.sh — MiTun shared utilities. Source only; do not execute.
#
# Usage: . "$(dirname "$0")/common_functions.sh"

DATA_DIR="/data/adb/mitun"
BIN_PATH="$DATA_DIR/mihomo"
CONFIG_PATH="$DATA_DIR/config.yaml"
RUN_DIR="$DATA_DIR/run"
PID_FILE="$RUN_DIR/mihomo.pid"
LOG_FILE="$RUN_DIR/mitun.log"
MIHOMO_LOG="$RUN_DIR/mihomo.log"

# Fixed TUN interface name. Keep in sync with `tun.device` in config.yaml;
# we do not validate at runtime — user is expected to leave the default.
TUN_DEVICE="mihomo"

# Log rotation threshold, in KiB.
LOG_MAX_KB="${LOG_MAX_KB:-1024}"

# ----- logging ---------------------------------------------------------------

_mitun_log() {
    _lvl="$1"; shift
    _ts="$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null)"
    _line="[$_ts] [$_lvl] $*"
    mkdir -p "$RUN_DIR" 2>/dev/null
    printf '%s\n' "$_line" >>"$LOG_FILE" 2>/dev/null
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
    printf '%s\n' "$$" >"$_lock/pid" 2>/dev/null
    return 0
}

release_lock() { rm -rf "$1" 2>/dev/null; }

# ----- pid / process ---------------------------------------------------------

read_pid() {
    [ -f "$PID_FILE" ] || return 0
    tr -d '[:space:]' <"$PID_FILE" 2>/dev/null
}

# is_running: 0 if mihomo is alive.
# Identity is checked against /proc/<pid>/cmdline to avoid PID-reuse
# misidentification. Unlike a naive substring grep (which matches e.g.
# `less /data/adb/mitun/mihomo.log`), we accept only:
#   (a) argv[0] basename == "mihomo", OR
#   (b) cmdline contains the exact $BIN_PATH absolute path as a NUL-separated
#       token (covers wrapper invocations without loosening to substrings).
# Side effect: removes stale PID_FILE on mismatch.
is_running() {
    _p="$(read_pid)"
    if [ -n "$_p" ] && [ "$_p" -gt 0 ] 2>/dev/null && [ -r "/proc/$_p/cmdline" ]; then
        _cmdline="$(tr '\0' '\n' <"/proc/$_p/cmdline" 2>/dev/null)"
        _argv0="$(printf '%s\n' "$_cmdline" | head -n 1)"
        _base="${_argv0##*/}"
        [ "$_base" = "mihomo" ] && return 0
        printf '%s\n' "$_cmdline" | grep -Fxq "$BIN_PATH" && return 0
    fi
    rm -f "$PID_FILE" 2>/dev/null
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
    if ip link show "$TUN_DEVICE" >/dev/null 2>&1; then
        ip link delete "$TUN_DEVICE" 2>/dev/null || true
    fi
}

# ----- lifecycle -------------------------------------------------------------

_stop_pid() {
    _p="$1"
    [ -n "$_p" ] && [ -d "/proc/$_p" ] || return 0
    kill -TERM "$_p" 2>/dev/null
    _w=0
    while [ "$_w" -lt 5 ] && [ -d "/proc/$_p" ]; do
        sleep 1
        _w=$((_w + 1))
    done
    [ -d "/proc/$_p" ] && kill -KILL "$_p" 2>/dev/null
    sleep 1
}

# Start lock — serializes concurrent start_mihomo invocations (service.sh vs
# boot-completed.sh vs action.sh). Blocks up to 60s, reclaims dead holders.
_acquire_start_lock() {
    mkdir -p "$RUN_DIR"
    _lock="$RUN_DIR/start.lock"
    _tries=0
    while [ "$_tries" -lt 60 ]; do
        try_lock "$_lock" && return 0
        sleep 1
        _tries=$((_tries + 1))
    done
    return 1
}

_release_start_lock() { release_lock "$RUN_DIR/start.lock"; }

# Idempotent: returns 0 if already running. Concurrent callers are serialized
# and collapse into a single exec via the start lock.
start_mihomo() {
    if is_running; then
        log_info "already running, pid=$(read_pid)"
        return 0
    fi

    if ! _acquire_start_lock; then
        log_error "start-lock timeout"
        return 1
    fi

    _do_start_mihomo
    _rc=$?
    _release_start_lock
    return "$_rc"
}

_do_start_mihomo() {
    # Re-check under lock — a concurrent caller may have won the race.
    if is_running; then
        log_info "already running, pid=$(read_pid)"
        return 0
    fi

    if [ ! -x "$BIN_PATH" ]; then
        log_error "mihomo binary missing or not executable: $BIN_PATH"
        return 1
    fi
    if [ ! -f "$CONFIG_PATH" ]; then
        log_error "config missing: $CONFIG_PATH"
        return 1
    fi

    ensure_tun_device || return 1
    mkdir -p "$RUN_DIR"

    rotate_log_if_big "$MIHOMO_LOG"
    rotate_log_if_big "$LOG_FILE"

    # Stale TUN from a crashed previous run
    _cleanup_tun

    # nohup only (no setsid) so $! is guaranteed to be mihomo's PID.
    nohup "$BIN_PATH" -d "$DATA_DIR" >>"$MIHOMO_LOG" 2>&1 &
    _pid=$!

    sleep 1
    if ! [ -d "/proc/$_pid" ]; then
        log_error "mihomo exited immediately — check $MIHOMO_LOG"
        return 1
    fi

    printf '%s\n' "$_pid" >"$PID_FILE"
    log_info "started, pid=$_pid"

    if ! wait_for_tun "$TUN_DEVICE" 10; then
        log_error "TUN '$TUN_DEVICE' did not appear within 10s"
        _stop_pid "$_pid"
        rm -f "$PID_FILE" 2>/dev/null
        _cleanup_tun
        return 1
    fi

    log_info "TUN '$TUN_DEVICE' is up"
    return 0
}

# Idempotent. Symmetric with start: always cleans TUN on exit.
stop_mihomo() {
    _p="$(read_pid)"
    if [ -z "$_p" ] || ! [ -d "/proc/$_p" ]; then
        rm -f "$PID_FILE" 2>/dev/null
        _cleanup_tun
        return 0
    fi
    _stop_pid "$_p"
    rm -f "$PID_FILE" 2>/dev/null
    _cleanup_tun
    log_info "stopped, pid=$_p"
    return 0
}
