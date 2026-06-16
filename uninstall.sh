#!/system/bin/sh
# uninstall.sh — stops the active core and removes module runtime files.
# User configs and binaries under /data/adb/mitun are preserved.

MODDIR="${0%/*}"
. "$MODDIR/common_functions.sh"

stop_core

# Remove runtime files we created. Keep configs and anything the user
# placed under $DATA_DIR manually. Drop $RUN_DIR last: any log_info after
# this line would recreate the directory and defeat the uninstall.
rm -rf "$RUN_DIR"
