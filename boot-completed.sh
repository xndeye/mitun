#!/system/bin/sh
# boot-completed.sh - autostart entry point after boot completes.
#
# start_core is internally locked to avoid races with the Action button.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

sleep 10

if is_running; then
    log_info "already running after boot, pid=$(read_pid)"
else
    if ! detect_core; then
        log_error "no supported core found — skipping boot autostart"
        exit 0
    fi

    log_info "boot completed — starting core"
    if start_core; then
        log_info "boot autostart OK, pid=$(read_pid)"
    else
        log_error "boot autostart failed — check $(core_log_path)"
    fi
fi
