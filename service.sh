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
    log_error "timed out waiting for sys.boot_completed; deferring to boot-completed hook"
    exit 0
fi

# Small grace for network bring-up
sleep 5

if ! detect_core; then
    log_error "no supported core found — skipping start"
    exit 0
fi

start_core
