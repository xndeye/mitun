#!/system/bin/sh
# service.sh — KernelSU late_start entry point for MiTun.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

# Wait for boot_completed (up to 60s)
_w=0
while [ "$_w" -lt 60 ]; do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 1
    _w=$((_w + 1))
done

if [ "$(getprop sys.boot_completed)" != "1" ]; then
    log_error "timed out waiting for sys.boot_completed; starting anyway"
fi

# Small grace for network bring-up
sleep 5

if [ ! -f "$CONFIG_PATH" ]; then
    log_error "config not found at $CONFIG_PATH — skipping start"
    exit 0
fi
if [ ! -x "$BIN_PATH" ]; then
    log_error "mihomo not found at $BIN_PATH — skipping start"
    exit 0
fi

start_mihomo
