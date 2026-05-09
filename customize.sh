#!/system/bin/sh
# customize.sh — MiTun installer. Sourced by update-binary.

DATA_DIR="/data/adb/mitun"
CONFIG_PATH="$DATA_DIR/config.yaml"

ui_print "- installing MiTun"

mkdir -p "$DATA_DIR/run"

if [ ! -f "$CONFIG_PATH" ]; then
    cp "$MODPATH/files/config.yaml.example" "$CONFIG_PATH"
    set_perm "$CONFIG_PATH" 0 0 0600
    ui_print "- installed example config -> $CONFIG_PATH"
fi

set_perm "$MODPATH/service.sh"          0 0 0755
set_perm "$MODPATH/boot-completed.sh"   0 0 0755
set_perm "$MODPATH/uninstall.sh"        0 0 0755
set_perm "$MODPATH/action.sh"           0 0 0755
set_perm "$MODPATH/common_functions.sh" 0 0 0644

ui_print "- done; place mihomo at $DATA_DIR/mihomo (chmod 0755), edit $CONFIG_PATH, then reboot"
