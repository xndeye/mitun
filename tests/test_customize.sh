#!/bin/sh
# tests/test_customize.sh
# shunit2-compatible tests for customize.sh
#
# Run on Linux/macOS:
#   sh tests/test_customize.sh
#
# Requires shunit2 to be installed or available in PATH.
# On Debian/Ubuntu: apt-get install shunit2
# On macOS:         brew install shunit2

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CUSTOMIZE_SH="$SCRIPT_DIR/customize.sh"

if [ ! -f "$CUSTOMIZE_SH" ]; then
    echo "ERROR: customize.sh not found at $CUSTOMIZE_SH" >&2
    exit 1
fi

# Mock: abort — print message and exit with error
abort() {
    echo "ABORT: $*" >&2
    exit 1
}

# Mock: ui_print — suppress output during tests
ui_print() {
    :
}

# Mock: set_perm — no-op (no root required)
set_perm() {
    :
}

TEST_TMP=""

setUp() {
    TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'mitun_customize_test')"

    MODPATH="$TEST_TMP/modpath"
    mkdir -p "$MODPATH/files"
    mkdir -p "$MODPATH/tools"

    printf '#!/bin/sh\necho fake-mihomo-arm64\n' > "$MODPATH/files/mihomo"
    chmod 755 "$MODPATH/files/mihomo"

    printf 'fake-geoip-data\n'    > "$MODPATH/files/GeoIP.dat"
    printf 'fake-geosite-data\n'  > "$MODPATH/files/GeoSite.dat"
    printf 'fake-metadb-data\n'   > "$MODPATH/files/geoip.metadb"

    printf 'tun:\n  enable: true\n  device: Meta\n' > "$MODPATH/files/config.yaml.example"

    touch "$MODPATH/service.sh"
    touch "$MODPATH/boot-completed.sh"
    touch "$MODPATH/uninstall.sh"
    touch "$MODPATH/action.sh"
    touch "$MODPATH/common_functions.sh"

    printf '#!/bin/sh\necho MITUN_CTL\n' > "$MODPATH/tools/mitun_ctl.sh"

    DATA_DIR="$TEST_TMP/mihomo"
    BIN_PATH="$DATA_DIR/mihomo"
    CONFIG_PATH="$DATA_DIR/config.yaml"

    ARCH="arm64"
    API="33"
    KSU="true"
    KSU_VER="0.9.0"
    KSU_VER_CODE="9000"
    ZIPFILE="$TEST_TMP/fake.zip"
}

tearDown() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
    TEST_TMP=""
}

# Run the installation logic from customize.sh with test paths
_run_install() {
    export DATA_DIR MODPATH ARCH API KSU KSU_VER KSU_VER_CODE ZIPFILE
    # shellcheck source=../customize.sh
    . "$CUSTOMIZE_SH"
    BIN_PATH="$DATA_DIR/mihomo"
    CONFIG_PATH="$DATA_DIR/config.yaml"
}

# Existing config.yaml is NOT overwritten during installation
test_config_preservation_existing_config_unchanged() {
    mkdir -p "$DATA_DIR"
    _original_content="# User config - DO NOT OVERWRITE
proxies:
  - name: my-proxy
    type: ss
    server: 1.2.3.4
    port: 8388
"
    printf '%s' "$_original_content" > "$CONFIG_PATH"
    _before="$(cat "$CONFIG_PATH")"
    _run_install
    _after="$(cat "$CONFIG_PATH")"
    assertEquals \
        "Config_File content must be identical after installation" \
        "$_before" "$_after"
}

# Config file still exists after installation
test_config_preservation_file_still_exists() {
    mkdir -p "$DATA_DIR"
    printf 'proxies: []\n' > "$CONFIG_PATH"
    _run_install
    assertTrue \
        "Config_File must still exist after installation" \
        "[ -f '$CONFIG_PATH' ]"
}

# When no config exists, example config is installed
test_config_installed_when_absent() {
    mkdir -p "$DATA_DIR"
    rm -f "$CONFIG_PATH"
    _run_install
    assertTrue \
        "Config_File should be created from example when absent" \
        "[ -f '$CONFIG_PATH' ]"
}

# When no config exists, installed config matches example
test_config_installed_matches_example() {
    mkdir -p "$DATA_DIR"
    rm -f "$CONFIG_PATH"
    _example_content="$(cat "$MODPATH/files/config.yaml.example")"
    _run_install
    _installed="$(cat "$CONFIG_PATH")"
    assertEquals \
        "Installed config must match example config when no prior config exists" \
        "$_example_content" "$_installed"
}

# Existing config with arbitrary content is preserved verbatim
test_config_preservation_arbitrary_content() {
    mkdir -p "$DATA_DIR"
    for _variant in \
        "mode: global" \
        "mode: rule
tun:
  enable: false" \
        "# empty-ish config
port: 7890
"; do
        printf '%s' "$_variant" > "$CONFIG_PATH"
        _before="$(cat "$CONFIG_PATH")"
        _run_install
        _after="$(cat "$CONFIG_PATH")"
        assertEquals \
            "Config_File must be preserved verbatim for variant: $_variant" \
            "$_before" "$_after"
    done
}

# Binary is copied to BIN_PATH during installation
test_binary_installed_to_bin_path() {
    mkdir -p "$DATA_DIR"
    _run_install
    assertTrue \
        "Mihomo binary must be installed to BIN_PATH" \
        "[ -f '$BIN_PATH' ]"
}

# Directory structure is created
test_data_dir_structure_created() {
    rm -rf "$DATA_DIR"
    _run_install
    assertTrue "DATA_DIR must be created"     "[ -d '$DATA_DIR' ]"
    assertTrue "DATA_DIR/run must be created" "[ -d '$DATA_DIR/run' ]"
}

# GeoData files are installed when absent
test_geodata_installed_when_absent() {
    mkdir -p "$DATA_DIR"
    rm -f "$DATA_DIR/GeoIP.dat" "$DATA_DIR/GeoSite.dat" "$DATA_DIR/geoip.metadb"
    _run_install
    assertTrue "GeoIP.dat must be installed"    "[ -f '$DATA_DIR/GeoIP.dat' ]"
    assertTrue "GeoSite.dat must be installed"  "[ -f '$DATA_DIR/GeoSite.dat' ]"
    assertTrue "geoip.metadb must be installed" "[ -f '$DATA_DIR/geoip.metadb' ]"
}

# GeoData files are NOT overwritten when they already exist
test_geodata_preserved_when_present() {
    mkdir -p "$DATA_DIR"
    printf 'user-geoip\n'    > "$DATA_DIR/GeoIP.dat"
    printf 'user-geosite\n'  > "$DATA_DIR/GeoSite.dat"
    printf 'user-metadb\n'   > "$DATA_DIR/geoip.metadb"
    _run_install
    assertEquals "GeoIP.dat must be preserved"    "user-geoip"    "$(cat "$DATA_DIR/GeoIP.dat")"
    assertEquals "GeoSite.dat must be preserved"  "user-geosite"  "$(cat "$DATA_DIR/GeoSite.dat")"
    assertEquals "geoip.metadb must be preserved" "user-metadb"   "$(cat "$DATA_DIR/geoip.metadb")"
}

# skip_mount marker is created in MODPATH
test_skip_mount_created() {
    mkdir -p "$DATA_DIR"
    _run_install
    assertTrue \
        "skip_mount marker must be created in MODPATH" \
        "[ -f '$MODPATH/skip_mount' ]"
}

# mitun_ctl.sh is copied to DATA_DIR
test_mitun_ctl_installed() {
    mkdir -p "$DATA_DIR"
    _run_install
    assertTrue \
        "mitun_ctl.sh must be installed to DATA_DIR" \
        "[ -f '$DATA_DIR/mitun_ctl.sh' ]"
}

# API level check: abort when API < 26
test_abort_on_low_api() {
    mkdir -p "$DATA_DIR"
    API="25"
    _result="$(
        export DATA_DIR MODPATH ARCH API KSU KSU_VER KSU_VER_CODE ZIPFILE
        abort() { echo "ABORT_CALLED"; exit 0; }
        ui_print() { :; }
        set_perm() { :; }
        . "$CUSTOMIZE_SH" 2>/dev/null
        echo "NO_ABORT"
    )"
    case "$_result" in
        *ABORT_CALLED*) assertTrue "abort() was called for API < 26" true ;;
        *) fail "abort() must be called when API < 26 (got: $_result)" ;;
    esac
}

# Architecture check: abort when ARCH is unsupported
test_abort_on_unsupported_arch() {
    mkdir -p "$DATA_DIR"
    API="33"
    ARCH="x86_64"
    _result="$(
        export DATA_DIR MODPATH ARCH API KSU KSU_VER KSU_VER_CODE ZIPFILE
        abort() { echo "ABORT_CALLED"; exit 0; }
        ui_print() { :; }
        set_perm() { :; }
        . "$CUSTOMIZE_SH" 2>/dev/null
        echo "NO_ABORT"
    )"
    case "$_result" in
        *ABORT_CALLED*) assertTrue "abort() was called for unsupported arch" true ;;
        *) fail "abort() must be called for unsupported architecture (got: $_result)" ;;
    esac
}

# arm architecture is NOT supported (only arm64 is)
test_arm_architecture_not_supported() {
    mkdir -p "$DATA_DIR"
    ARCH="arm"
    API="33"
    _result="$(
        export DATA_DIR MODPATH ARCH API KSU KSU_VER KSU_VER_CODE ZIPFILE
        abort() { echo "ABORT_CALLED"; exit 0; }
        ui_print() { :; }
        set_perm() { :; }
        . "$CUSTOMIZE_SH" 2>/dev/null
        echo "NO_ABORT"
    )"
    case "$_result" in
        *ABORT_CALLED*) assertTrue "abort() was called for arm (only arm64 is supported)" true ;;
        *) fail "abort() must be called for arm architecture (got: $_result)" ;;
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
