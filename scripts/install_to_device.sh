#!/usr/bin/env bash
set -e

# ==============================================================================
# mlxLLM: Direct Deployment to Paired iPad Pro (M4) / iPhone via devicectl
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_APP="$PROJECT_ROOT/dist/Payload/mlxLLM.app"

XCODE_APP="/Users/henryluo/Downloads/Xcode.app"
export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

if [ ! -d "$DIST_APP" ]; then
    echo "Dist app not found. Running package_ipa.sh first..."
    "$SCRIPT_DIR/package_ipa.sh"
fi

echo "=================================================="
echo "  mlxLLM Direct Device Deployment Helper"
echo "=================================================="

# Check connected devices
echo "Scanning for connected paired devices..."
DEVICES=$(xcrun devicectl list devices)
echo "$DEVICES"
echo "--------------------------------------------------"

IPAD_UDID="A7A102C3-6B19-5C47-BC9F-046B9B394062"
IPHONE_UDID="B99013EE-6FC3-52B0-B8A7-134D6E582390"

TARGET_DEVICE="${1:-$IPAD_UDID}"

echo "Installing $DIST_APP to device ($TARGET_DEVICE)..."
xcrun devicectl device install app --device "$TARGET_DEVICE" "$DIST_APP"

echo "=================================================="
echo "  Installation Complete on Device! "
echo "=================================================="
