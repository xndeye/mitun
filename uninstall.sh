#!/system/bin/sh
# uninstall.sh — KernelSU MiTun Module
# Executed by KernelSU when the module is uninstalled.
# Stops the Mihomo process, removes runtime files, and preserves user config.

MODDIR="$(dirname "$0")"
. "$MODDIR/common_functions.sh"

# Stop Mihomo process gracefully (also removes PID_FILE internally)
stop_mihomo

# Remove remaining runtime files
rm -f "$LOG_FILE"

# User config ($CONFIG_PATH) and $DATA_DIR are intentionally NOT deleted

log_info "MiTun has been uninstalled."
log_info "User data preserved at: $DATA_DIR"
log_info "To fully remove all data, run: rm -rf $DATA_DIR"
