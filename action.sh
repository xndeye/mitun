#!/system/bin/sh
# action.sh — toggled when the user taps the Action button in KernelSU manager.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

if ! _acquire_lifecycle_lock; then
    ksud module config set override.description "⏳ Another MiTun operation is in progress or runtime directory setup failed." 2>/dev/null || true
    echo "⏳ Another MiTun operation is in progress or runtime directory setup failed."
    exit 1
fi
trap '_release_lifecycle_lock' EXIT INT TERM

if is_running; then
    if _do_stop_core; then
        ksud module config set override.description "⏹ MiTun stopped." 2>/dev/null || true
        echo "⏹ MiTun stopped."
    else
        ksud module config set override.description "❌ MiTun failed to stop — check $LOG_FILE" 2>/dev/null || true
        echo "❌ MiTun failed to stop — check $LOG_FILE"
        exit 1
    fi
else
    if _do_start_core; then
        ksud module config set override.description "▶ MiTun started." 2>/dev/null || true
        echo "▶ MiTun started."
    else
        ksud module config set override.description "❌ MiTun failed to start — check $(core_log_path)" 2>/dev/null || true
        echo "❌ MiTun failed to start — check $(core_log_path)"
        exit 1
    fi
fi
