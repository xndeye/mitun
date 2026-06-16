#!/system/bin/sh
# boot-completed.sh — post-boot health check.
#
# service.sh is the primary start path. This hook performs one guarded retry
# after boot completion; start_core's lock keeps it race-safe with Action.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

sleep 10

if is_running; then
    log_info "health check OK, pid=$(read_pid)"
else
    if ! detect_core; then
        log_error "no supported core found — skipping boot retry"
        exit 0
    fi

    log_error "not running after boot — retrying start once"
    if start_core; then
        log_info "boot retry OK, pid=$(read_pid)"
    else
        log_error "boot retry failed — check $(core_log_path)"
    fi
fi
