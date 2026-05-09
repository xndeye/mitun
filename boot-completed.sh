#!/system/bin/sh
# boot-completed.sh — post-boot health check.
#
# service.sh is the single start path; this script only observes and logs.
# It deliberately does NOT call start_mihomo: keeping one start path avoids
# the boot / Action race entirely.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

sleep 10

if is_running; then
    log_info "health check OK, pid=$(read_pid)"
else
    log_error "not running after boot — check $MIHOMO_LOG (start via Action button if needed)"
fi
