#!/bin/sh
# tests/test_validate_config.sh
# shunit2-compatible tests for the 'validate' sub-command in tools/mitun_ctl.sh
#
# Run on Linux/macOS:
#   sh tests/test_validate_config.sh
#
# Requires shunit2 to be installed or available in PATH.
# On Debian/Ubuntu: apt-get install shunit2
# On macOS:         brew install shunit2

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MITUN_CTL_SRC="$REPO_DIR/tools/mitun_ctl.sh"
COMMON_FUNCTIONS_SRC="$REPO_DIR/common_functions.sh"

if [ ! -f "$MITUN_CTL_SRC" ]; then
    echo "ERROR: mitun_ctl.sh not found at $MITUN_CTL_SRC" >&2
    exit 1
fi

if [ ! -f "$COMMON_FUNCTIONS_SRC" ]; then
    echo "ERROR: common_functions.sh not found at $COMMON_FUNCTIONS_SRC" >&2
    exit 1
fi

TEST_TMP=""
MITUN_CTL=""

setUp() {
    TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'mitun_validate_test')"

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

    # Copy scripts into a temp dir so mitun_ctl.sh can source common_functions.sh
    # with test-specific paths patched in.
    SCRIPTS_DIR="$TEST_TMP/scripts"
    mkdir -p "$SCRIPTS_DIR"
    cp "$MITUN_CTL_SRC" "$SCRIPTS_DIR/mitun_ctl.sh"

    sed \
        -e "s|DATA_DIR=\"/data/adb/mitun\"|DATA_DIR=\"$DATA_DIR\"|" \
        -e "s|BIN_PATH=\"\$DATA_DIR/mihomo\"|BIN_PATH=\"$BIN_PATH\"|" \
        -e "s|CONFIG_PATH=\"\$DATA_DIR/config.yaml\"|CONFIG_PATH=\"$CONFIG_PATH\"|" \
        -e "s|PID_FILE=\"\$DATA_DIR/run/mihomo.pid\"|PID_FILE=\"$PID_FILE\"|" \
        -e "s|LOG_FILE=\"\$DATA_DIR/run/mihomo.log\"|LOG_FILE=\"$LOG_FILE\"|" \
        "$COMMON_FUNCTIONS_SRC" > "$SCRIPTS_DIR/common_functions.sh"

    MITUN_CTL="$SCRIPTS_DIR/mitun_ctl.sh"

    export DATA_DIR BIN_PATH CONFIG_PATH PID_FILE LOG_FILE TUN_DEVICE \
           API_HOST API_PORT API_SECRET
}

tearDown() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
    TEST_TMP=""
}

# Run the validate sub-command; captures output into _validate_output
_run_validate() {
    _validate_output="$(
        DATA_DIR="$DATA_DIR" \
        BIN_PATH="$BIN_PATH" \
        CONFIG_PATH="$CONFIG_PATH" \
        PID_FILE="$PID_FILE" \
        LOG_FILE="$LOG_FILE" \
        TUN_DEVICE="$TUN_DEVICE" \
        API_HOST="$API_HOST" \
        API_PORT="$API_PORT" \
        API_SECRET="$API_SECRET" \
        sh "$MITUN_CTL" validate 2>&1
    )"
    return $?
}

# Create a mock mihomo binary
#   $1 = exit code (0 = valid, non-zero = invalid)
#   $2 = optional stderr message
_create_mock_binary() {
    _exit_code="${1:-0}"
    _msg="${2:-}"
    mkdir -p "$(dirname "$BIN_PATH")"
    if [ -n "$_msg" ]; then
        printf '#!/bin/sh\nprintf "%%s\\n" "%s" >&2\nexit %s\n' \
            "$_msg" "$_exit_code" > "$BIN_PATH"
    else
        printf '#!/bin/sh\nexit %s\n' "$_exit_code" > "$BIN_PATH"
    fi
    chmod 755 "$BIN_PATH"
}

_create_config() {
    _content="$1"
    printf '%s\n' "$_content" > "$CONFIG_PATH"
}

# Config file not found → non-zero exit code
test_validate_config_not_found_returns_error() {
    _create_mock_binary 0
    rm -f "$CONFIG_PATH"
    _run_validate
    _rc=$?
    assertNotEquals \
        "validate should return non-zero when config file does not exist" \
        0 "$_rc"
}

# Config file not found → descriptive error message
test_validate_config_not_found_outputs_descriptive_message() {
    _create_mock_binary 0
    rm -f "$CONFIG_PATH"
    _run_validate || true
    case "$_validate_output" in
        *"ERROR"*|*"not found"*|*"error"*)
            assertTrue "Output contains descriptive error message" true ;;
        *)
            fail "validate output missing descriptive error message: $_validate_output" ;;
    esac
}

# mihomo -t returns non-zero → validate returns non-zero
test_validate_mihomo_syntax_error_returns_nonzero() {
    _create_config "invalid: yaml: content"
    _create_mock_binary 1 "time=\"2024-01-01\" level=fatal msg=\"invalid config\""
    _run_validate
    _rc=$?
    assertNotEquals \
        "validate should return non-zero when mihomo -t fails" \
        0 "$_rc"
}

# mihomo -t returns non-zero → stderr content is shown
test_validate_mihomo_syntax_error_outputs_stderr_content() {
    _create_config "bad: yaml"
    _create_mock_binary 1 "invalid config: missing required field"
    _run_validate || true
    case "$_validate_output" in
        *"invalid config"*|*"ERROR"*|*"failed"*)
            assertTrue "Output contains mihomo error content" true ;;
        *)
            fail "validate output missing mihomo error content: $_validate_output" ;;
    esac
}

# tun.enable not true → warning
test_validate_tun_enable_missing_outputs_warning() {
    _create_config "mode: rule
log-level: info
tun:
  stack: mixed
  device: Meta
  auto-route: true"
    _create_mock_binary 0
    _run_validate || true
    case "$_validate_output" in
        *"WARNING"*|*"warning"*|*"tun"*|*"TUN"*)
            assertTrue "Output contains warning about tun.enable" true ;;
        *)
            fail "validate output missing tun.enable warning: $_validate_output" ;;
    esac
}

# tun.enable: false → warning
test_validate_tun_enable_false_outputs_warning() {
    _create_config "tun:
  enable: false
  auto-route: true"
    _create_mock_binary 0
    _run_validate || true
    case "$_validate_output" in
        *"WARNING"*|*"warning"*|*"tun"*|*"TUN"*|*"enable"*)
            assertTrue "Output contains warning when tun.enable is false" true ;;
        *)
            fail "validate output missing warning for tun.enable: false: $_validate_output" ;;
    esac
}

# tun.auto-route not true → warning
test_validate_auto_route_missing_outputs_warning() {
    _create_config "tun:
  enable: true
  stack: mixed
  device: Meta"
    _create_mock_binary 0
    _run_validate || true
    case "$_validate_output" in
        *"WARNING"*|*"warning"*|*"auto-route"*|*"routing"*)
            assertTrue "Output contains warning about tun.auto-route" true ;;
        *)
            fail "validate output missing auto-route warning: $_validate_output" ;;
    esac
}

# tun.auto-route: false → warning
test_validate_auto_route_false_outputs_warning() {
    _create_config "tun:
  enable: true
  auto-route: false"
    _create_mock_binary 0
    _run_validate || true
    case "$_validate_output" in
        *"WARNING"*|*"warning"*|*"auto-route"*|*"routing"*)
            assertTrue "Output contains warning when tun.auto-route is false" true ;;
        *)
            fail "validate output missing warning for tun.auto-route: false: $_validate_output" ;;
    esac
}

# Valid config with proper TUN settings → exit 0
test_validate_valid_config_returns_success() {
    _create_config "mode: rule
log-level: info
tun:
  enable: true
  stack: mixed
  device: Meta
  auto-route: true
  auto-redirect: true"
    _create_mock_binary 0
    _run_validate
    _rc=$?
    assertEquals \
        "validate should return 0 for valid config with proper TUN settings" \
        0 "$_rc"
}

# Valid config → output indicates success
test_validate_valid_config_outputs_ok_message() {
    _create_config "tun:
  enable: true
  auto-route: true"
    _create_mock_binary 0
    _run_validate || true
    case "$_validate_output" in
        *"OK"*|*"ok"*|*"valid"*|*"success"*)
            assertTrue "Output indicates config is valid" true ;;
        *)
            fail "validate output missing success indicator: $_validate_output" ;;
    esac
}

# Binary not found → non-zero exit code
test_validate_binary_not_found_returns_error() {
    _create_config "tun:
  enable: true
  auto-route: true"
    rm -f "$BIN_PATH"
    _run_validate
    _rc=$?
    assertNotEquals \
        "validate should return non-zero when mihomo binary is missing" \
        0 "$_rc"
}

# Binary not found → descriptive error message
test_validate_binary_not_found_outputs_descriptive_message() {
    _create_config "tun:
  enable: true
  auto-route: true"
    rm -f "$BIN_PATH"
    _run_validate || true
    case "$_validate_output" in
        *"ERROR"*|*"error"*|*"not found"*|*"binary"*)
            assertTrue "Output contains descriptive error for missing binary" true ;;
        *)
            fail "validate output missing descriptive error for missing binary: $_validate_output" ;;
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
