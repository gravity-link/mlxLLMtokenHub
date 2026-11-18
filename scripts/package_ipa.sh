#!/usr/bin/env bash
set -e

# ==============================================================================
# mlxLLM: iOS / iPadOS Sideload & Dynamic Signing IPA Packaging Script
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="mlxLLM"
BUNDLE_ID="com.mlxmesh.llm"
TARGET_TRIPLE="arm64-apple-ios17.0"

XCODE_APP="/Users/henryluo/Downloads/Xcode.app"
export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
SDK_PATH="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk"

if [ ! -d "$SDK_PATH" ]; then
    # Fallback to dynamic lookup
    SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
fi

echo "=================================================="
echo "  Packaging $APP_NAME for Sideload & Dynamic Signing"
echo "=================================================="
echo "• Project Root:  $PROJECT_ROOT"
echo "• Xcode Path:    $DEVELOPER_DIR"
echo "• iPhoneOS SDK:  $SDK_PATH"
echo "• Target Arch:   $TARGET_TRIPLE (Apple Silicon iOS/iPadOS)"
echo "--------------------------------------------------"

cd "$PROJECT_ROOT"
mkdir -p "$DIST_DIR"

# 1. Compile Release Objects for iOS
echo "[1/6] Compiling Swift modules for $TARGET_TRIPLE (Release mode)..."
xcrun swift build -c release --triple "$TARGET_TRIPLE" --sdk "$SDK_PATH"

RELEASE_BUILD_DIR="$PROJECT_ROOT/.build/arm64-apple-ios/release"

# 2. Link Executable Mach-O Binary
echo "[2/6] Linking Mach-O executable ($APP_NAME)..."
TEMP_APP_DIR="$DIST_DIR/Payload/$APP_NAME.app"
rm -rf "$DIST_DIR/Payload"
mkdir -p "$TEMP_APP_DIR"

xcrun -sdk "$SDK_PATH" clang \
  -target "$TARGET_TRIPLE" \
  -isysroot "$SDK_PATH" \
  -O3 \
  "$RELEASE_BUILD_DIR/MLXMeshCore.build"/*.o \
  "$RELEASE_BUILD_DIR/MLXMeshNetworking.build"/*.o \
  "$RELEASE_BUILD_DIR/MLXMeshEngine.build"/*.o \
  "$RELEASE_BUILD_DIR/MLXMeshApp.build"/*.o \
  -framework Foundation -framework UIKit -framework SwiftUI -framework Network -framework Accelerate \
  -fobjc-link-runtime \
  -L"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos" \
  -o "$TEMP_APP_DIR/$APP_NAME"

chmod +x "$TEMP_APP_DIR/$APP_NAME"

# 3. Create PkgInfo and Info.plist
echo "[3/6] Generating Info.plist & Entitlements..."
echo -n "APPL????" > "$TEMP_APP_DIR/PkgInfo"

cat << 'EOF' > "$TEMP_APP_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>mlxLLM</string>
    <key>CFBundleIdentifier</key>
    <string>com.mlxmesh.llm</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>mlxLLM</string>
    <key>CFBundleDisplayName</key>
    <string>mlxLLM</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>NSLocalNetworkUsageDescription</key>
    <string>mlxLLM requires local and WAN network access to discover peer compute nodes via libp2p-quic.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_mlxmesh._udp</string>
        <string>_libp2p._udp</string>
    </array>
    <key>UIBackgroundModes</key>
    <array>
        <string>processing</string>
        <string>remote-notification</string>
    </array>
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>com.mlxmesh.llm.speculative</string>
    </array>
    <key>CFBundleIcons</key>
    <dict>
        <key>CFBundlePrimaryIcon</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon60x60</string>
                <string>AppIcon76x76</string>
                <string>AppIcon83.5x83.5</string>
            </array>
            <key>CFBundleIconName</key>
            <string>AppIcon</string>
        </dict>
    </dict>
    <key>UILaunchScreen</key>
    <dict/>
</dict>
</plist>
EOF

cat << 'EOF' > "$DIST_DIR/Entitlements.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>get-task-allow</key>
    <true/>
    <key>com.apple.developer.kernel.increased-memory-limit</key>
    <true/>
    <key>com.apple.developer.kernel.extended-virtual-addressing</key>
    <true/>
</dict>
</plist>
EOF

# 4. Generate App Icons if needed
echo "[4/6] Generating and copying App Icons..."
if [ ! -f "$DIST_DIR/AppIcon1024.png" ]; then
    swift -e '
    import AppKit
    let size = CGSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.07, green: 0.08, blue: 0.15, alpha: 1.0).cgColor,
        NSColor(red: 0.12, green: 0.15, blue: 0.35, alpha: 1.0).cgColor,
        NSColor(red: 0.28, green: 0.15, blue: 0.55, alpha: 1.0).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    ctx.setStrokeColor(NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.8).cgColor)
    ctx.setLineWidth(24)
    ctx.strokeEllipse(in: CGRect(x: 160, y: 160, width: 704, height: 704))
    let center = CGPoint(x: 512, y: 512)
    let nodeCount = 6
    var points: [CGPoint] = []
    for i in 0..<nodeCount {
        let angle = Double(i) * (2.0 * .pi / Double(nodeCount)) - .pi / 2.0
        let radius: Double = 260.0
        points.append(CGPoint(x: center.x + CGFloat(cos(angle) * radius), y: center.y + CGFloat(sin(angle) * radius)))
    }
    ctx.setLineWidth(10)
    ctx.setStrokeColor(NSColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 0.5).cgColor)
    for i in 0..<nodeCount {
        for j in (i+1)..<nodeCount { ctx.strokeLineSegments(between: [points[i], points[j]]) }
        ctx.strokeLineSegments(between: [center, points[i]])
    }
    ctx.setFillColor(NSColor(red: 1.0, green: 0.45, blue: 0.2, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140))
    ctx.setFillColor(NSColor(red: 0.25, green: 0.85, blue: 0.55, alpha: 1.0).cgColor)
    for pt in points { ctx.fillEllipse(in: CGRect(x: pt.x - 42, y: pt.y - 42, width: 84, height: 84)) }
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 64),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle
    ]
    let str = NSAttributedString(string: "M4", attributes: attrs)
    str.draw(in: CGRect(x: center.x - 60, y: center.y - 40, width: 120, height: 80))
    image.unlockFocus()
    if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: "dist/AppIcon1024.png"))
    }
    '
fi

sips -z 180 180 "$DIST_DIR/AppIcon1024.png" --out "$TEMP_APP_DIR/AppIcon60x60@3x.png" > /dev/null
sips -z 120 120 "$DIST_DIR/AppIcon1024.png" --out "$TEMP_APP_DIR/AppIcon60x60@2x.png" > /dev/null
sips -z 167 167 "$DIST_DIR/AppIcon1024.png" --out "$TEMP_APP_DIR/AppIcon83.5x83.5@2x.png" > /dev/null
sips -z 152 152 "$DIST_DIR/AppIcon1024.png" --out "$TEMP_APP_DIR/AppIcon76x76@2x.png" > /dev/null
cp "$DIST_DIR/AppIcon1024.png" "$TEMP_APP_DIR/AppIcon1024.png"

# 5. Ad-Hoc / Sideload Code Signing
echo "[5/6] Code signing bundle (Ad-Hoc / Sideload Ready)..."
codesign -s - --force --deep --preserve-metadata=identifier,flags,runtime --entitlements "$DIST_DIR/Entitlements.plist" "$TEMP_APP_DIR"

# 6. Assemble .ipa Zip Archives
echo "[6/6] Packaging into .ipa archives..."
cd "$DIST_DIR"
rm -f "$DIST_DIR/mlxLLM-sideload.ipa" "$DIST_DIR/mlxLLM.ipa" "$DIST_DIR/mlxLLM-temporary-sideload.ipa"
zip -qry "$DIST_DIR/mlxLLM.ipa" Payload
cp "$DIST_DIR/mlxLLM.ipa" "$DIST_DIR/mlxLLM-sideload.ipa"
cp "$DIST_DIR/mlxLLM.ipa" "$DIST_DIR/mlxLLM-temporary-sideload.ipa"

# Also package developer-signed iPadM4 IPA if profile exists
DEV_PROFILE="/Users/henryluo/Library/Developer/Xcode/UserData/Provisioning Profiles/450bb77b-b566-4653-8d97-2b5fb3b4c71b.mobileprovision"
if [ -f "$DEV_PROFILE" ]; then
    echo "• Packaging developer-signed iPadM4 package..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.webrtc.subscriber" "$TEMP_APP_DIR/Info.plist" 2>/dev/null || true
    cp "$DEV_PROFILE" "$TEMP_APP_DIR/embedded.mobileprovision"
    codesign -s "Apple Development: Hongyu Luo (32VR253K2K)" -f --entitlements "$DIST_DIR/real_entitlements.plist" "$TEMP_APP_DIR" 2>/dev/null || true
    rm -f "$DIST_DIR/mlxLLM-iPadM4.ipa"
    zip -qry "$DIST_DIR/mlxLLM-iPadM4.ipa" Payload
fi

IPA_SIZE=$(du -h "$DIST_DIR/mlxLLM.ipa" | cut -f1)

echo "=================================================="
echo "  Build & Sideload Package Created Successfully!   "
echo "=================================================="
echo "• Output IPA:        $DIST_DIR/mlxLLM.ipa ($IPA_SIZE)"
echo "• Sideload IPA:      $DIST_DIR/mlxLLM-sideload.ipa"
echo "• Temp Sideload IPA: $DIST_DIR/mlxLLM-temporary-sideload.ipa"
echo "• iPad M4 Direct:    $DIST_DIR/mlxLLM-iPadM4.ipa"
echo "• Raw App:           $TEMP_APP_DIR"
echo ""
echo "支持的签名与安装方式："
echo "1. 【Sideloadly / AltStore / SideStore / 牛蛙助手】"
echo "   直接将 $DIST_DIR/mlxLLM.ipa 拖拽到工具中，输入个人免费 Apple ID 即可自动自签名并安装到 iPad / iPhone。"
echo "2. 【TrollStore 巨魔商店 (免越狱永久安装)】"
echo "   若设备为 iOS 14.0-16.6.1 / 17.0 TrollStore，直接将 mlxLLM.ipa 隔空投送 (AirDrop) 或在设备上使用 TrollStore 打开，即刻享受永久免证书签名与全内存提权。"
echo "3. 【轻松签 ESign / 全能签 / 共享动态签名服务】"
echo "   在 iOS 设备通过 Safari 或已安装的轻松签直接导入 mlxLLM.ipa，选择企业证书或个人证书一键动态签名安装。"
echo "4. 【本地直连免工具安装 (针对已配对的 iPad Pro 11(M4) 或 iPhone 16e)】"
echo "   运行: ./scripts/install_to_device.sh"
echo "=================================================="
