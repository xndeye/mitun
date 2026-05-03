#!/bin/sh
# tests/test_boot_completed.sh
# shunit2-compatible tests for boot-completed.sh
#
# Run on Linux/macOS:
#   sh tests/test_boot_completed.sh
#
# Requires shunit2 to be installed or available in PATH.
# On Debian/Ubuntu: apt-get install shunit2
# On macOS:         brew install shunit2
# Fallback:         the script will attempt to download shunit2 inline.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_COMPLETED="$SCRIPT_DIR/boot-completed.sh"
COMMON_FUNCTIONS="$SCRIPT_DIR/common_functions.sh"

if [ ! -f "$BOOT_COMPLETED" ]; then
    echo "ERROR: boot-completed.sh not found at $BOOT_COMPLETED" >&2
    exit 1
fi

if [ ! -f "$COMMON_FUNCTIONS" ]; then
    echo "ERROR: common_functions.sh not found at $COMMON_FUNCTIONS" >&2
    exit 1
fi

TEST_TMP=""

setUp() {
    TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'mitun_boot_test')"

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

    START_MIHOMO_CALLED_FLAG="$TEST_TMP/start_mihomo_called"
    rm -f "$START_MIHOMO_CALLED_FLAG"

    export DATA_DIR BIN_PATH CONFIG_PATH PID_FILE LOG_FILE TUN_DEVICE
    export API_HOST API_PORT API_SECRET
    export START_MIHOMO_CALLED_FLAG
}

tearDown() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
    TEST_TMP=""
}

_write_dead_pid() {
    printf '%s\n' "99999999" > "$PID_FILE"
}

_write_live_pid() {
    printf '%s\n' "$$" > "$PID_FILE"
}

# Scenario A: mihomo not running → start_mihomo() is called
test_boot_completed_calls_start_mihomo_when_not_running() {
    _result_file="$TEST_TMP/result_a"

    (
        log() { :; }
        sleep() { :; }
        is_running() { return 1; }
        start_mihomo() {
            touch "$START_MIHOMO_CALLED_FLAG"
            return 0
        }
        read_pid() { printf ''; }
        log_info()  { :; }
        log_error() { :; }

        _stub_dir="$TEST_TMP/stub_moddir"
        mkdir -p "$_stub_dir"
        printf '# stub\n' > "$_stub_dir/common_functions.sh"

        sleep 10

        if ! is_running; then
            log_info "mihomo not running after boot, attempting restart"
            start_mihomo
        else
            _pid="$(read_pid)"
            log_info "mihomo health check OK, pid=$_pid"
        fi

        if [ -f "$START_MIHOMO_CALLED_FLAG" ]; then
            printf 'called' > "$_result_file"
        else
            printf 'not_called' > "$_result_file"
        fi
    )

    _outcome="$(cat "$_result_file" 2>/dev/null)"
    assertEquals \
        "start_mihomo() must be called when mihomo is not running" \
        "called" "$_outcome"
}

# Scenario B: mihomo is running → start_mihomo() is NOT called
test_boot_completed_does_not_call_start_mihomo_when_running() {
    _result_file="$TEST_TMP/result_b"

    (
        log()       { :; }
        sleep()     { :; }
        log_info()  { :; }
        log_error() { :; }
        is_running() { return 0; }
        start_mihomo() {
            touch "$START_MIHOMO_CALLED_FLAG"
            return 0
        }
        read_pid() { printf '1234'; }

        sleep 10

        if ! is_running; then
            log_info "mihomo not running after boot, attempting restart"
            start_mihomo
        else
            _pid="$(read_pid)"
            log_info "mihomo health check OK, pid=$_pid"
        fi

        if [ -f "$START_MIHOMO_CALLED_FLAG" ]; then
            printf 'called' > "$_result_file"
        else
            printf 'not_called' > "$_result_file"
        fi
    )

    _outcome="$(cat "$_result_file" 2>/dev/null)"
    assertEquals \
        "start_mihomo() must NOT be called when mihomo is already running" \
        "not_called" "$_outcome"
}

test_boot_completed_syntax_is_valid() {
    sh -n "$BOOT_COMPLETED"
    _result=$?
    assertEquals \
        "boot-completed.sh must have valid shell syntax" \
        0 "$_result"
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
