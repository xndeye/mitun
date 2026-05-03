#!/system/bin/sh
# action.sh — KernelSU MiTun Module
# Executed when the user taps the Action button in the KernelSU manager.
# Toggles MiTun: if running → stop mihomo (module stays enabled);
#                if stopped  → start mihomo.

MODDIR="$(dirname "$0")"
. "$MODDIR/common_functions.sh"

if is_running; then
    stop_mihomo
    log_info "action.sh: MiTun stopped"
    ksud module config set override.description "MiTun — stopped (tap Action to start)" 2>/dev/null || true
    echo "MiTun stopped."
else
    log_info "action.sh: starting MiTun"
    ensure_tun_device
    start_mihomo
    ksud module config set override.description "MiTun — running (tap Action to stop)" 2>/dev/null || true
    echo "MiTun started."
fi
