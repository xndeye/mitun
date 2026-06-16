#!/system/bin/sh
# customize.sh — MiTun installer. Sourced by update-binary.

DATA_DIR="/data/adb/mitun"
CONFIG_PATH="$DATA_DIR/config.yaml"

ui_print "- installing MiTun"

mkdir -p "$DATA_DIR" "$DATA_DIR/run" || exit 1
chown 0:0 "$DATA_DIR" "$DATA_DIR/run" 2>/dev/null || true
chmod 0700 "$DATA_DIR" "$DATA_DIR/run" 2>/dev/null || true

if [ ! -f "$CONFIG_PATH" ]; then
    cp "$MODPATH/files/config.yaml.example" "$CONFIG_PATH" || exit 1
    chown 0:0 "$CONFIG_PATH" 2>/dev/null || true
    chmod 0600 "$CONFIG_PATH" 2>/dev/null || true
    ui_print "- installed example config -> $CONFIG_PATH"
fi

set_perm "$MODPATH/service.sh"          0 0 0755
set_perm "$MODPATH/boot-completed.sh"   0 0 0755
set_perm "$MODPATH/uninstall.sh"        0 0 0755
set_perm "$MODPATH/action.sh"           0 0 0755
set_perm "$MODPATH/common_functions.sh" 0 0 0644

if [ -x "$DATA_DIR/mihomo" ]; then
    ui_print "- mihomo binary found"
else
    ui_print "- mihomo binary not found; place it at $DATA_DIR/mihomo and chmod 0755"
fi

ui_print "- done; edit $CONFIG_PATH, then reboot or use the Action button"
