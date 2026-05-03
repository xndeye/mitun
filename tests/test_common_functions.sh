#!/bin/sh
# tests/test_common_functions.sh
# shunit2-compatible tests for common_functions.sh
#
# Run on Linux/macOS:
#   sh tests/test_common_functions.sh
#
# Requires shunit2 to be installed or available in PATH.
# On Debian/Ubuntu: apt-get install shunit2
# On macOS:         brew install shunit2
# Fallback:         the script will attempt to download shunit2 inline.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMON_FUNCTIONS="$SCRIPT_DIR/common_functions.sh"

if [ ! -f "$COMMON_FUNCTIONS" ]; then
    echo "ERROR: common_functions.sh not found at $COMMON_FUNCTIONS" >&2
    exit 1
fi

# shellcheck source=../common_functions.sh
. "$COMMON_FUNCTIONS"

# Stub: Android 'log' command (not available on Linux/macOS)
# Defined AFTER sourcing so it overrides any definition in common_functions.sh
log() { :; }

# Stub: 'ip' command — controlled per-test via IP_STUB_RESULT
IP_STUB_RESULT=1
ip() {
    case "$1" in
        link)
            case "$2" in
                show)   return "$IP_STUB_RESULT" ;;
                delete) return 0 ;;
            esac
            ;;
    esac
    return 0
}

# Stub: 'setsid' — just exec the command directly
setsid() { "$@"; }

# Stub: 'nohup' — just exec the command directly
nohup() { "$@"; }

TEST_TMP=""

setUp() {
    TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'mitun_test')"

    DATA_DIR="$TEST_TMP/mihomo"
    BIN_PATH="$DATA_DIR/mihomo"
    CONFIG_PATH="$DATA_DIR/config.yaml"
    PID_FILE="$DATA_DIR/run/mihomo.pid"
    LOG_FILE="$DATA_DIR/run/mihomo.log"
    TUN_DEVICE="Meta"
    API_HOST="127.0.0.1"
    API_PORT="9090"
    API_SECRET=""

    mkdir -p "$DATA_DIR/run"

    IP_STUB_RESULT=1
}

tearDown() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
    TEST_TMP=""
}

_write_live_pid() {
    printf '%s\n' "$$" > "$PID_FILE"
}

_write_dead_pid() {
    printf '%s\n' "99999999" > "$PID_FILE"
}

_create_fake_binary() {
    printf '#!/bin/sh\nexit 0\n' > "$BIN_PATH"
    chmod 755 "$BIN_PATH"
}

_create_config() {
    printf 'tun:\n  enable: true\n' > "$CONFIG_PATH"
}

# is_running(): stale PID_FILE → returns false
test_is_running_stale_pid_returns_false() {
    _write_dead_pid
    is_running
    _result=$?
    assertNotEquals \
        "is_running() should return false when process is dead" \
        0 "$_result"
}

# is_running(): stale PID_FILE → file is cleaned up
test_is_running_stale_pid_cleans_up_pid_file() {
    _write_dead_pid
    assertTrue "PID_FILE should exist before is_running()" "[ -f '$PID_FILE' ]"
    is_running || true
    assertFalse \
        "is_running() should delete stale PID_FILE" \
        "[ -f '$PID_FILE' ]"
}

# is_running(): no PID_FILE → returns false
test_is_running_no_pid_file_returns_false() {
    rm -f "$PID_FILE"
    is_running
    _result=$?
    assertNotEquals \
        "is_running() should return false when PID_FILE absent" \
        0 "$_result"
}

# is_running(): live PID → returns true
test_is_running_live_pid_returns_true() {
    _write_live_pid
    is_running
    _result=$?
    assertEquals \
        "is_running() should return true when process is alive" \
        0 "$_result"
}

# wait_for_tun(): interface absent → timeout exit code
test_wait_for_tun_timeout_returns_1() {
    IP_STUB_RESULT=1
    wait_for_tun "Meta" 2
    _result=$?
    assertEquals \
        "wait_for_tun() should return 1 on timeout" \
        1 "$_result"
}

# wait_for_tun(): interface present → success exit code
test_wait_for_tun_success_returns_0() {
    IP_STUB_RESULT=0
    wait_for_tun "Meta" 5
    _result=$?
    assertEquals \
        "wait_for_tun() should return 0 when interface is up" \
        0 "$_result"
}

# wait_for_tun(): must not loop past timeout
test_wait_for_tun_respects_timeout_bound() {
    IP_STUB_RESULT=1
    _start="$(date +%s)"
    wait_for_tun "Meta" 1 || true
    _end="$(date +%s)"
    _elapsed=$((_end - _start))
    assertTrue \
        "wait_for_tun() must not exceed timeout+slack seconds (elapsed=${_elapsed}s)" \
        "[ '$_elapsed' -le 4 ]"
}

# start_mihomo(): already running → idempotent, PID unchanged
test_start_mihomo_idempotent_when_already_running() {
    _write_live_pid
    _original_pid="$(read_pid)"
    start_mihomo
    _result=$?
    assertEquals \
        "start_mihomo() should return 0 when already running" \
        0 "$_result"
    _current_pid="$(read_pid)"
    assertEquals \
        "PID_FILE content must not change on idempotent call" \
        "$_original_pid" "$_current_pid"
}

# start_mihomo(): multiple calls → PID unchanged (process uniqueness)
test_start_mihomo_process_uniqueness() {
    _write_live_pid
    _original_pid="$(read_pid)"
    start_mihomo || true
    start_mihomo || true
    _final_pid="$(read_pid)"
    assertEquals \
        "Multiple start_mihomo() calls must not change PID" \
        "$_original_pid" "$_final_pid"
}

# stop_mihomo(): not running → returns success, no PID_FILE
test_stop_mihomo_idempotent_when_not_running() {
    rm -f "$PID_FILE"
    stop_mihomo
    _result=$?
    assertEquals \
        "stop_mihomo() should return 0 when not running" \
        0 "$_result"
    assertFalse \
        "PID_FILE must not exist after stop_mihomo() when not running" \
        "[ -f '$PID_FILE' ]"
}

# stop_mihomo(): stale PID_FILE → cleaned up
test_stop_mihomo_cleans_stale_pid_file() {
    _write_dead_pid
    stop_mihomo
    _result=$?
    assertEquals \
        "stop_mihomo() should return 0 with stale PID_FILE" \
        0 "$_result"
    assertFalse \
        "stop_mihomo() must delete stale PID_FILE" \
        "[ -f '$PID_FILE' ]"
}

# stop_mihomo(): running process → terminated, PID_FILE deleted
test_stop_mihomo_terminates_running_process() {
    sleep 60 &
    _sleep_pid=$!
    printf '%s\n' "$_sleep_pid" > "$PID_FILE"
    assertTrue "Background process should be alive" "[ -d '/proc/$_sleep_pid' ]"
    stop_mihomo
    _result=$?
    assertEquals \
        "stop_mihomo() should return 0 after terminating process" \
        0 "$_result"
    assertFalse \
        "PID_FILE must be deleted after stop_mihomo()" \
        "[ -f '$PID_FILE' ]"
    sleep 1
    assertFalse \
        "Process must be terminated after stop_mihomo()" \
        "[ -d '/proc/$_sleep_pid' ]"
    kill -KILL "$_sleep_pid" 2>/dev/null || true
}

_assert_clean_state_after_failure() {
    _reason="$1"
    handle_startup_failure "$_reason"
    assertFalse \
        "PID_FILE must not exist after handle_startup_failure (reason: $_reason)" \
        "[ -f '$PID_FILE' ]"
}

test_handle_startup_failure_no_residual_pid_file_config_error() {
    _write_dead_pid
    _assert_clean_state_after_failure "config.yaml syntax error"
}

test_handle_startup_failure_no_residual_pid_file_tun_timeout() {
    _write_dead_pid
    _assert_clean_state_after_failure "TUN interface creation timeout"
}

test_handle_startup_failure_no_residual_pid_file_binary_missing() {
    _write_dead_pid
    _assert_clean_state_after_failure "mihomo binary not found"
}

# handle_startup_failure(): kills residual live process
test_handle_startup_failure_kills_residual_process() {
    sleep 60 &
    _sleep_pid=$!
    printf '%s\n' "$_sleep_pid" > "$PID_FILE"
    assertTrue "Residual process should be alive before failure handler" \
        "[ -d '/proc/$_sleep_pid' ]"
    handle_startup_failure "simulated failure"
    sleep 1
    assertFalse \
        "handle_startup_failure() must kill residual process" \
        "[ -d '/proc/$_sleep_pid' ]"
    assertFalse \
        "handle_startup_failure() must remove PID_FILE" \
        "[ -f '$PID_FILE' ]"
    kill -KILL "$_sleep_pid" 2>/dev/null || true
}

# handle_startup_failure(): attempts TUN interface cleanup
test_handle_startup_failure_attempts_tun_cleanup() {
    IP_STUB_RESULT=0
    _write_dead_pid
    handle_startup_failure "TUN residual cleanup test"
    assertFalse \
        "PID_FILE must be removed even when TUN cleanup is attempted" \
        "[ -f '$PID_FILE' ]"
}

test_read_pid_returns_empty_when_no_file() {
    rm -f "$PID_FILE"
    _pid="$(read_pid)"
    assertEquals "read_pid() should return empty string when no file" "" "$_pid"
}

test_read_pid_returns_empty_when_file_empty() {
    printf '' > "$PID_FILE"
    _pid="$(read_pid)"
    assertEquals "read_pid() should return empty string for empty file" "" "$_pid"
}

test_read_pid_strips_whitespace() {
    printf '  1234  \n' > "$PID_FILE"
    _pid="$(read_pid)"
    assertEquals "read_pid() should strip whitespace" "1234" "$_pid"
}

test_read_pid_returns_pid_value() {
    printf '5678\n' > "$PID_FILE"
    _pid="$(read_pid)"
    assertEquals "read_pid() should return the PID" "5678" "$_pid"
}

test_log_info_writes_to_log_file() {
    log_info "test info message"
    assertTrue "LOG_FILE should exist after log_info()" "[ -f '$LOG_FILE' ]"
    _content="$(cat "$LOG_FILE")"
    case "$_content" in
        *"[INFO]"*"test info message"*) assertTrue "log line contains INFO and message" true ;;
        *) fail "log_info() output missing [INFO] or message: $_content" ;;
    esac
}

test_log_error_writes_to_log_file() {
    log_error "test error message"
    assertTrue "LOG_FILE should exist after log_error()" "[ -f '$LOG_FILE' ]"
    _content="$(cat "$LOG_FILE")"
    case "$_content" in
        *"[ERROR]"*"test error message"*) assertTrue "log line contains ERROR and message" true ;;
        *) fail "log_error() output missing [ERROR] or message: $_content" ;;
    esac
}

test_log_info_format_has_timestamp() {
    log_info "timestamp test"
    _content="$(cat "$LOG_FILE")"
    case "$_content" in
        *"["*"-"*"-"*" "*":"*":"*"]"*) assertTrue "timestamp present" true ;;
        *) fail "log_info() output missing timestamp: $_content" ;;
    esac
}

_find_shunit2() {
    for _p in \
        /usr/share/shunit2/shunit2 \
        /usr/local/share/shunit2/shunit2 \
        /opt/homebrew/opt/shunit2/bin/shunit2 \
        /usr/bin/shunit2 \
        "$(command -v shunit2 2>/dev/null)"; do
        if [ -f "$_p" ]; then
            printf '%s' "$_p"
            return 0
        fi
    done
    return 1
}

SHUNIT2_PATH="$(_find_shunit2)"

if [ -z "$SHUNIT2_PATH" ]; then
    echo ""
    echo "shunit2 not found. Attempting to download shunit2 2.1.8 ..."
    _dl_dir="$(mktemp -d 2>/dev/null || mktemp -d -t shunit2_dl)"
    _shunit2_url="https://raw.githubusercontent.com/kward/shunit2/v2.1.8/shunit2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$_shunit2_url" -o "$_dl_dir/shunit2" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$_shunit2_url" -O "$_dl_dir/shunit2" 2>/dev/null
    fi
    if [ -f "$_dl_dir/shunit2" ]; then
        SHUNIT2_PATH="$_dl_dir/shunit2"
        echo "Downloaded shunit2 to $SHUNIT2_PATH"
    else
        echo "ERROR: Could not find or download shunit2." >&2
        echo "Install it with: apt-get install shunit2  OR  brew install shunit2" >&2
        exit 1
    fi
fi

# shellcheck source=/dev/null
. "$SHUNIT2_PATH"
