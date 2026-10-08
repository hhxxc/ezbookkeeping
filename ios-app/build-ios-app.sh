#!/bin/bash
# ============================================================================
# NestKeep 原生 iOS App —— 构建并导出 IPA（用于 TrollStore 安装）
#
# 前置条件（在 Mac 上执行本脚本）：
#   1. 安装 Xcode 15+ 与 Command Line Tools (xcode-select --install)
#   2. Xcode 中登录你的 Apple ID（Xcode > Settings > Accounts），
#      并在 NestKeep target 的 Signing & Capabilities 里选好 Team
#      （本工程已设为 Automatic 签名，选 Team 即可，无需付费账号）
#   3. 本脚本与 NestKeep.xcodeproj 同级目录
#
# 用法：
#   ./build-ios-app.sh            # 默认 Release，导出 IPA 到 ./build/NestKeep.ipa
#   CONFIG=Debug ./build-ios-app.sh
#
# 不想用脚本也可以：Xcode 打开 NestKeep.xcodeproj → Product > Archive → 导出 IPA。
# 拿到 IPA 后 AirDrop / 文件 App 传到 iPhone → 用 TrollStore 打开安装（会重新签名，永久驻留）。
# ============================================================================
set -euo pipefail

CONFIG="${CONFIG:-Release}"
SCHEME="NestKeep"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
PROJ="$WORKDIR/NestKeep.xcodeproj"
BUILD="$WORKDIR/build"
ARCHIVE="$BUILD/NestKeep.xcarchive"
EXPORT="$BUILD/export"
IPA="$BUILD/NestKeep.ipa"

echo "==> 清理旧产物"
rm -rf "$BUILD"
mkdir -p "$EXPORT"

echo "==> Archive ($CONFIG)"
xcodebuild archive \
    -project "$PROJ" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk iphoneos \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Automatic

echo "==> Export IPA"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$WORKDIR/exportOptions.plist" \
    -exportPath "$EXPORT"

# export 目录下通常是 NestKeep.ipa
if [ -f "$EXPORT/NestKeep.ipa" ]; then
    cp "$EXPORT/NestKeep.ipa" "$IPA"
    echo ""
    echo "==> 成功：$IPA"
    echo "    把该 IPA 传到 iPhone，用 TrollStore 打开即可安装（重新签名，永久驻留）。"
else
    echo "未找到导出的 IPA，export 目录内容："
    ls -la "$EXPORT"
fi
