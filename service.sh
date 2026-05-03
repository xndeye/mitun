#!/system/bin/sh
# service.sh — KernelSU MiTun Module
# Executed by KernelSU in the late_start service phase.
# Waits for boot completion, checks prerequisites, and starts Mihomo.

MODDIR="$(dirname "$0")"
. "$MODDIR/common_functions.sh"

# Wait for sys.boot_completed=1 (timeout 60 seconds)
_waited=0
while [ "$_waited" -lt 60 ]; do
    if [ "$(getprop sys.boot_completed)" = "1" ]; then
        break
    fi
    sleep 1
    _waited=$((_waited + 1))
done

# Extra 5-second delay to ensure network is ready
sleep 5

# Check config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    log_error "config.yaml not found: $CONFIG_PATH — skipping Mihomo start"
    exit 0
fi

# Check Mihomo binary exists and is executable
if [ ! -x "$BIN_PATH" ]; then
    log_error "mihomo binary not found or not executable: $BIN_PATH — skipping Mihomo start"
    exit 0
fi

# Ensure /dev/net/tun device node exists
ensure_tun_device

# Start Mihomo
start_mihomo

ksud module config set override.description "MiTun — running (tap Action to disable)" 2>/dev/null || true
