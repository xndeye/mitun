#!/system/bin/sh
# action.sh — toggled when the user taps the Action button in KernelSU manager.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

LOCK_DIR="$RUN_DIR/action.lock"

mkdir -p "$RUN_DIR"

if ! try_lock "$LOCK_DIR"; then
    ksud module config set override.description "⏳ Another MiTun action is in progress." 2>/dev/null || true
    echo "⏳ Another MiTun action is in progress."
    exit 1
fi
trap 'release_lock "$LOCK_DIR"' EXIT INT TERM

if is_running; then
    stop_mihomo
    ksud module config set override.description "⏹ MiTun stopped." 2>/dev/null || true
    echo "⏹ MiTun stopped."
else
    if start_mihomo; then
        ksud module config set override.description "▶ MiTun started." 2>/dev/null || true
        echo "▶ MiTun started."
    else
        ksud module config set override.description "❌ MiTun failed to start — check $MIHOMO_LOG" 2>/dev/null || true
        echo "❌ MiTun failed to start — check $MIHOMO_LOG"
        exit 1
    fi
fi
