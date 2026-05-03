#!/bin/sh
# build.sh — KernelSU MiTun Module
# Packages the module source into a KernelSU-installable zip file.
#
# Usage: sh build.sh

set -e

# Read version from module.prop
if [ ! -f "module.prop" ]; then
    echo "ERROR: module.prop not found. Run this script from the module root directory." >&2
    exit 1
fi

VERSION="$(grep '^version=' module.prop | cut -d= -f2)"
VERSION_CODE="$(grep '^versionCode=' module.prop | cut -d= -f2)"

if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read 'version' from module.prop" >&2
    exit 1
fi

if [ -z "$VERSION_CODE" ]; then
    echo "ERROR: Could not read 'versionCode' from module.prop" >&2
    exit 1
fi

OUTPUT_ZIP="mitun-${VERSION}.zip"

echo "Building MiTun Module ${VERSION} (versionCode=${VERSION_CODE})"
echo ""

# Check required files exist before packaging
REQUIRED_FILES="
module.prop
service.sh
customize.sh
boot-completed.sh
uninstall.sh
skip_mount
common_functions.sh
tools/mitun_ctl.sh
files/config.yaml.example
files/ui.zip
sepolicy.rule
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
"

_missing=0
for _file in $REQUIRED_FILES; do
    if [ ! -f "$_file" ]; then
        echo "ERROR: Required file missing: $_file" >&2
        _missing=$((_missing + 1))
    fi
done

if [ "$_missing" -gt 0 ]; then
    echo "" >&2
    echo "Build failed: $_missing required file(s) missing." >&2
    exit 1
fi

echo "All required files present."

# Package module files into zip
# Exclude: .git/, *.md, build.sh, tests/, .kiro/, *.zip
rm -f "$OUTPUT_ZIP"

echo "Creating ${OUTPUT_ZIP} ..."

zip -r "$OUTPUT_ZIP" . \
    --exclude "*.git*" \
    --exclude "*.md" \
    --exclude "build.sh" \
    --exclude "tests/*" \
    --exclude ".kiro/*" \
    --exclude "*.zip" \
    --exclude ".gitkeep" \
    --exclude "*.DS_Store"

if command -v du >/dev/null 2>&1; then
    _size="$(du -sh "$OUTPUT_ZIP" 2>/dev/null | cut -f1)"
else
    _size="unknown"
fi

echo ""
echo "Build complete!"
echo "  Output : ${OUTPUT_ZIP}"
echo "  Size   : ${_size}"
echo "  Version: ${VERSION} (versionCode=${VERSION_CODE})"
echo ""
echo "Install via KernelSU: adb push ${OUTPUT_ZIP} /sdcard/ && install from KernelSU app"
