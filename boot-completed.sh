#!/system/bin/sh
# boot-completed.sh — KernelSU MiTun Module
# Health check script executed after system boot completes.
# Waits for network to be fully ready, then checks if mihomo is running
# and attempts a restart if it is not.

MODDIR="$(dirname "$0")"
. "$MODDIR/common_functions.sh"

# Wait for network to be fully ready after boot
sleep 10

# Health check: restart if not running, log OK with PID if running
if ! is_running; then
    log_info "mihomo not running after boot, attempting restart"
    start_mihomo
else
    _pid="$(read_pid)"
    log_info "mihomo health check OK, pid=$_pid"
fi

ksud module config set override.description "MiTun — running (tap Action to disable)" 2>/dev/null || true
