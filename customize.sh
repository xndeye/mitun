#!/system/bin/sh
# customize.sh — MiTun installer. Sourced by update-binary.

DATA_DIR="/data/adb/mitun"
MIHOMO_EXAMPLE_PATH="$DATA_DIR/config.yaml.example"
SING_BOX_EXAMPLE_PATH="$DATA_DIR/config.json.example"

ui_print "- installing MiTun"

mkdir -p "$DATA_DIR" "$DATA_DIR/run" || exit 1
chown 0:0 "$DATA_DIR" "$DATA_DIR/run" 2>/dev/null || true
chmod 0700 "$DATA_DIR" "$DATA_DIR/run" 2>/dev/null || true

if [ ! -f "$MIHOMO_EXAMPLE_PATH" ]; then
    cp "$MODPATH/files/config.yaml.example" "$MIHOMO_EXAMPLE_PATH" || exit 1
    chown 0:0 "$MIHOMO_EXAMPLE_PATH" 2>/dev/null || true
    chmod 0600 "$MIHOMO_EXAMPLE_PATH" 2>/dev/null || true
    ui_print "- copied example config -> $MIHOMO_EXAMPLE_PATH"
fi

if [ ! -f "$SING_BOX_EXAMPLE_PATH" ]; then
    cp "$MODPATH/files/config.json.example" "$SING_BOX_EXAMPLE_PATH" || exit 1
    chown 0:0 "$SING_BOX_EXAMPLE_PATH" 2>/dev/null || true
    chmod 0600 "$SING_BOX_EXAMPLE_PATH" 2>/dev/null || true
    ui_print "- copied example config -> $SING_BOX_EXAMPLE_PATH"
fi

set_perm "$MODPATH/service.sh"          0 0 0755
set_perm "$MODPATH/boot-completed.sh"   0 0 0755
set_perm "$MODPATH/uninstall.sh"        0 0 0755
set_perm "$MODPATH/action.sh"           0 0 0755
set_perm "$MODPATH/common_functions.sh" 0 0 0644

if [ -x "$DATA_DIR/mihomo" ] && [ -f "$DATA_DIR/config.yaml" ]; then
    ui_print "- mihomo core found"
elif [ -x "$DATA_DIR/sing-box" ] && [ -f "$DATA_DIR/config.json" ]; then
    ui_print "- sing-box core found"
else
    ui_print "- no runnable core found"
    ui_print "  mihomo:   $DATA_DIR/mihomo + $DATA_DIR/config.yaml"
    ui_print "  sing-box: $DATA_DIR/sing-box + $DATA_DIR/config.json"
fi

ui_print "- examples are copied with the .example suffix only"
ui_print "- copy an edited example to config.yaml or config.json before starting"
ui_print "- done; prepare config, then reboot or use the Action button"
