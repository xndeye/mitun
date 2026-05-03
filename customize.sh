#!/system/bin/sh
# customize.sh — KernelSU MiTun Module
# Installation customization script.
# Sourced by META-INF/com/google/android/update-binary during installation.
#
# Variables provided by the KernelSU installer:
#   $ARCH         — CPU architecture (arm64, arm, x86, x64)
#   $API          — Android API level (integer)
#   $MODPATH      — Module installation directory
#   $ZIPFILE      — Path to the module zip file
#   $KSU          — Always true in KernelSU context
#   $KSU_VER      — KernelSU version string
#   $KSU_VER_CODE — KernelSU version code (integer)

# Path constants (must match common_functions.sh)
# Allow override via environment for testing purposes.
DATA_DIR="${DATA_DIR:-/data/adb/mitun}"
BIN_PATH="$DATA_DIR/mihomo"
CONFIG_PATH="$DATA_DIR/config.yaml"

# Pre-installation checks

# Require Android 8.0+ (API >= 26)
if [ "$API" -lt 26 ] 2>/dev/null; then
    abort "Android 8.0+ required (API >= 26)"
fi

# Only arm64 is supported
if [ "$ARCH" != "arm64" ]; then
    abort "Only arm64 architecture is supported"
fi

ui_print "*****************************"
ui_print "*        MiTun Module       *"
ui_print "*****************************"
ui_print "* Architecture: $ARCH"
ui_print "* Android API:  $API"
ui_print "*"

check_and_install_binary() {
    mkdir -p "$DATA_DIR"
    mkdir -p "$DATA_DIR/run"

    cp "$MODPATH/files/mihomo" "$BIN_PATH"
    set_perm "$BIN_PATH" 0 0 0755

    # Only copy GeoData files if they don't already exist (preserve user version)
    for _geofile in GeoIP.dat GeoSite.dat geoip.metadb; do
        if [ ! -f "$DATA_DIR/$_geofile" ]; then
            cp "$MODPATH/files/$_geofile" "$DATA_DIR/$_geofile"
        fi
    done

    # Extract Web UI (always overwrite to keep UI up-to-date with module version)
    if [ -f "$MODPATH/files/ui.zip" ]; then
        ui_print "* Installing Web UI..."
        rm -rf "$DATA_DIR/ui"
        mkdir -p "$DATA_DIR/ui"
        unzip -qo "$MODPATH/files/ui.zip" -d "$DATA_DIR/ui"
        # zashboard dist.zip extracts into a dist/ subdirectory — flatten it
        if [ -d "$DATA_DIR/ui/dist" ]; then
            mv "$DATA_DIR/ui/dist/"* "$DATA_DIR/ui/"
            rmdir "$DATA_DIR/ui/dist"
        fi
        ui_print "* Web UI installed to $DATA_DIR/ui"
    fi

    # Install example config only if config.yaml does not exist
    if [ ! -f "$CONFIG_PATH" ]; then
        cp "$MODPATH/files/config.yaml.example" "$CONFIG_PATH"
        ui_print "* Default config installed."
        ui_print "* Please edit $CONFIG_PATH to configure your proxy."
    fi
}

check_and_install_binary

# Remove files directory to free up space after installation
rm -rf "$MODPATH/files"
ui_print "* Cleaned up installation files."

# Post-installation steps

# Install control script to data directory
cp "$MODPATH/tools/mitun_ctl.sh" "$DATA_DIR/mitun_ctl.sh"
set_perm "$DATA_DIR/mitun_ctl.sh" 0 0 0755

# Set module script permissions
set_perm "$MODPATH/service.sh"        0 0 0755
set_perm "$MODPATH/boot-completed.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh"      0 0 0755
set_perm "$MODPATH/action.sh"         0 0 0755
set_perm "$MODPATH/common_functions.sh" 0 0 0644

# This module does not modify /system
touch "$MODPATH/skip_mount"

# Root read/write only for config
set_perm "$CONFIG_PATH" 0 0 0600

ui_print "* Installation complete!"
ui_print "* Edit config: $CONFIG_PATH"
ui_print "* Reboot to start MiTun"
