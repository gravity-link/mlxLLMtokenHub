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

echo "Target Device: $TARGET_DEVICE"

# Check if screen is locked
CHECK_LOCK=$(xcrun devicectl device info lockState -d "$TARGET_DEVICE" 2>/dev/null | grep "passcodeRequired: true" || true)

if [ -n "$CHECK_LOCK" ]; then
    echo ""
    echo "⚠️  【重要提示】检测到 iPad Pro 处于锁屏或熄屏状态！"
    echo "👉 请点亮您的 iPad Pro 屏幕并输入密码解锁（或通过 Face ID 解锁）。"
    echo "正在等待设备解锁并自动开始部署（最长等待 45 秒）..."
    
    WAITED=0
    while [ $WAITED -lt 45 ]; do
        sleep 2
        WAITED=$((WAITED + 2))
        IS_LOCKED=$(xcrun devicectl device info lockState -d "$TARGET_DEVICE" 2>/dev/null | grep "passcodeRequired: true" || true)
        if [ -z "$IS_LOCKED" ]; then
            echo "✅ 设备已解锁！立即开始推入安装..."
            break
        fi
        echo -n "."
    done
    echo ""
fi

echo "正在将 $DIST_APP 安装到设备 ($TARGET_DEVICE)..."
xcrun devicectl device install app --device "$TARGET_DEVICE" "$DIST_APP"

echo ""
echo "🚀 正在 iPad Pro M4 上启动 mlxLLM..."
xcrun devicectl device process launch --device "$TARGET_DEVICE" com.webrtc.subscriber || true

echo ""
echo "=================================================="
echo "  🎉 部署成功！mlxLLM 已成功安装并启动在 iPad Pro M4！"
echo "=================================================="
