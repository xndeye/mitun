#!/system/bin/sh
# uninstall.sh — stops mihomo and removes module-installed runtime files.
# User config at $CONFIG_PATH is preserved.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

stop_mihomo

# Remove runtime files we created. Keep config.yaml and anything the user
# placed under $DATA_DIR manually. Drop $RUN_DIR last: any log_info after
# this line would recreate the directory and defeat the uninstall.
rm -rf "$RUN_DIR"
