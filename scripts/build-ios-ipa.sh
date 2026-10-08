#!/usr/bin/env bash
#
# 本地 macOS 构建「巢记」iOS IPA（供 TrollStore 安装）
#
# 默认：把网页（dist/）直接打包进 IPA，App 内 WebView 加载本地网页（离线可开），
#       数据请求走 NAS 后端（由 API_BASE_URL 指定）。即「把网页打包成 IPA」。
# 可选远程兜底：传入 SERVER_URL 时改用 Capacitor server.url 远程加载 NAS 上的网页。
#
# 用法:
#   # 默认本地打包（连 NAS 后端 https://example-server.invalid）
#   API_BASE_URL=https://example-server.invalid VERSION=1.6.0.1 ./scripts/build-ios-ipa.sh
#
#   # 可选：远程加载模式（IPA 只作薄壳，加载 SERVER_URL 上的网页）
#   SERVER_URL=https://example-server.invalid VERSION=1.6.0.1 ./scripts/build-ios-ipa.sh
#
# 环境变量:
#   API_BASE_URL   本地打包模式：网页 App 连接的后端地址，默认 https://example-server.invalid
#   SERVER_URL     可选，传入则改用远程加载模式（壳加载的服务器地址，会自动补 /mobile）
#   VERSION        IPA 自身版本号，用于 App 内更新检查，默认 1.6.0.0
#
# 注意：iOS 15.0~15.3 的 WebKit 没有解锁 WKWebView 120Hz 的接口（见
#       scripts/ios-shell-unlock.swift），本机若为此系统，120Hz 解锁不生效，需升级 iOS 16+。
#
# 前置依赖 (macOS):
#   - Xcode + 命令行工具
#   - Node.js (建议 24)
#   - CocoaPods (sudo gem install cocoapods)
#   - npm / npx
#
# 产出:
#   ./nestkeep.ipa
#   构建采用 CODE_SIGNING_ALLOWED=NO 免签名 archive + ad-hoc 自签，
#   TrollStore 安装时会用自己的证书重新签名，无需付费开发者账号。
#
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://example-server.invalid}"
SERVER_URL="${SERVER_URL:-}"           # 留空 = 本地打包；传入 = 远程加载模式
SHELL_VERSION="${VERSION:-1.6.0.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export API_BASE_URL SERVER_URL SHELL_VERSION

echo ">>> [1/12] 安装依赖"
npm install

echo ">>> [2/12] 写入版本号到 package.json"
node -e "const fs=require('fs');const p=require('./package.json');p.version=process.env.SHELL_VERSION;fs.writeFileSync('./package.json',JSON.stringify(p,null,2)+'\n');"

echo ">>> [3/12] 构建 Web"
npm run build

if [ -n "$SERVER_URL" ]; then
  echo ">>> [4/12] 远程加载模式：用 ios-shell 作为跳转壳"
  test -f ios-shell/index.html
  cp ios-shell/index.html dist/index.html
  node -e "
const fs=require('fs');
let html=fs.readFileSync('dist/index.html','utf8');
html=html.split('__NESTKEEP_DEFAULT_SERVER__').join(process.env.SERVER_URL||'');
html=html.split('__NESTKEEP_FALLBACK_SERVER__').join('');
html=html.split('__NESTKEEP_SHELL_VERSION__').join(process.env.SHELL_VERSION||'');
fs.writeFileSync('dist/index.html',html);
"
  if grep -q '__NESTKEEP_DEFAULT_SERVER__\|__NESTKEEP_SHELL_VERSION__' dist/index.html; then
    echo "ERROR: dist/index.html 中仍有未替换的占位符"; exit 1
  fi
  echo "    远程服务器: ${SERVER_URL}"
else
  echo ">>> [4/12] 本地打包模式：注入 API 后端地址 + 复制诊断页"
  node -e "
const fs=require('fs');
let html=fs.readFileSync('dist/index.html','utf8');
const inject='<script>window.EZBOOKKEEPING_SERVER_SETTINGS={apiBaseUrl:\"'+process.env.API_BASE_URL+'\"};</script>';
html=html.replace('</head>', inject+'\n</head>');
fs.writeFileSync('dist/index.html',html);
"
  cp ios-shell/index.html dist/shell-diag.html
  echo "    API 后端地址: ${API_BASE_URL}"
fi
echo "    Shell 版本:    ${SHELL_VERSION}"

echo ">>> [5/12] 安装 Capacitor iOS 平台依赖"
npm install @capacitor/core@7 @capacitor/cli@7 @capacitor/ios@7

echo ">>> [6/12] 添加 iOS 平台 (若已存在则跳过)"
test -d ios || npx cap add ios

if [ -n "$SERVER_URL" ]; then
  echo ">>> [7/12] 同步 iOS（远程加载模式，注入 server.url）"
  NESTKEEP_SHELL_SERVER_URL="$SERVER_URL" NESTKEEP_SHELL_VERSION="$SHELL_VERSION" npx cap sync ios
  if ! grep -q '"url"' ios/App/App/capacitor.config.json; then
    echo "ERROR: server.url 未注入 ios/App/App/capacitor.config.json"; exit 1
  fi
else
  echo ">>> [7/12] 同步 iOS（本地打包模式，加载包内 dist，不注入 server.url）"
  NESTKEEP_SHELL_VERSION="$SHELL_VERSION" npx cap sync ios
fi

echo ">>> [8/12] 修补 Info.plist (ATS 放行 / 120Hz / 相机·相册权限)"
PLIST="ios/App/App/Info.plist"
PB=/usr/libexec/PlistBuddy
$PB -c "Delete :NSAppTransportSecurity" "$PLIST" >/dev/null 2>&1 || true
$PB -c "Add :NSAppTransportSecurity dict" "$PLIST"
$PB -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool false" "$PLIST"
$PB -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoadsInWebContent bool true" "$PLIST"
$PB -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST"
$PB -c "Delete :CADisableMinimumFrameDurationOnPhone" "$PLIST" >/dev/null 2>&1 || true
$PB -c "Add :CADisableMinimumFrameDurationOnPhone bool true" "$PLIST"
$PB -c "Delete :NSCameraUsageDescription" "$PLIST" >/dev/null 2>&1 || true
$PB -c "Add :NSCameraUsageDescription string 巢记需要使用相机拍摄小票照片用于记账" "$PLIST"
$PB -c "Delete :NSPhotoLibraryUsageDescription" "$PLIST" >/dev/null 2>&1 || true
$PB -c "Add :NSPhotoLibraryUsageDescription string 巢记需要访问照片图库以选择小票图片用于 AI 识别记账" "$PLIST"
$PB -c "Delete :NSPhotoLibraryAddUsageDescription" "$PLIST" >/dev/null 2>&1 || true
$PB -c "Add :NSPhotoLibraryAddUsageDescription string 巢记需要将识别相关图片保存到照片图库" "$PLIST"

echo ">>> [9/12] 注入 120Hz 到 AppDelegate"
node scripts/ios-shell-fps-inject.js

echo ">>> [10/12] 生成 App 图标"
npm install --no-save sharp >/dev/null 2>&1
node -e "
const fs=require('fs');const sharp=require('sharp');
let svg=fs.readFileSync('public/nestkeep-logo.svg','utf8');
svg=svg.replace(/x=\"16\" y=\"16\" width=\"480\" height=\"480\" rx=\"112\"/g,'x=\"0\" y=\"0\" width=\"512\" height=\"512\" rx=\"0\"');
sharp(Buffer.from(svg)).resize(1024,1024).png().toFile('/tmp/nestkeep_icon.png');
"
DST="ios/App/App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$DST"
for s in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do
  sips -z $s $s /tmp/nestkeep_icon.png --out "$DST/icon-${s}.png"
done
cat > "$DST/Contents.json" << 'EOF'
{
  "images": [
    { "size": "20x20", "idiom": "iphone", "filename": "icon-40.png", "scale": "2x" },
    { "size": "20x20", "idiom": "iphone", "filename": "icon-60.png", "scale": "3x" },
    { "size": "29x29", "idiom": "iphone", "filename": "icon-58.png", "scale": "2x" },
    { "size": "29x29", "idiom": "iphone", "filename": "icon-87.png", "scale": "3x" },
    { "size": "40x40", "idiom": "iphone", "filename": "icon-80.png", "scale": "2x" },
    { "size": "40x40", "idiom": "iphone", "filename": "icon-120.png", "scale": "3x" },
    { "size": "60x60", "idiom": "iphone", "filename": "icon-120.png", "scale": "2x" },
    { "size": "60x60", "idiom": "iphone", "filename": "icon-180.png", "scale": "3x" },
    { "size": "20x20", "idiom": "ipad", "filename": "icon-20.png", "scale": "1x" },
    { "size": "20x20", "idiom": "ipad", "filename": "icon-40.png", "scale": "2x" },
    { "size": "29x29", "idiom": "ipad", "filename": "icon-29.png", "scale": "1x" },
    { "size": "29x29", "idiom": "ipad", "filename": "icon-58.png", "scale": "2x" },
    { "size": "40x40", "idiom": "ipad", "filename": "icon-40.png", "scale": "1x" },
    { "size": "40x40", "idiom": "ipad", "filename": "icon-80.png", "scale": "2x" },
    { "size": "76x76", "idiom": "ipad", "filename": "icon-76.png", "scale": "1x" },
    { "size": "76x76", "idiom": "ipad", "filename": "icon-152.png", "scale": "2x" },
    { "size": "83.5x83.5", "idiom": "ipad", "filename": "icon-167.png", "scale": "2x" },
    { "size": "1024x1024", "idiom": "ios-marketing", "filename": "icon-1024.png", "scale": "1x" }
  ],
  "info": { "version": 1, "author": "xcode" }
}
EOF

echo ">>> [11/12] 安装 CocoaPods 依赖"
cd ios/App
pod install
cd "$ROOT_DIR"

echo ">>> [12/12] 构建 IPA (免签名 archive + 自签)"
rm -rf Payload App.xcarchive
xcodebuild \
  -workspace ios/App/App.xcworkspace \
  -scheme App \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/App.xcarchive" \
  archive \
  CODE_SIGNING_ALLOWED=NO
mkdir -p Payload
cp -R "App.xcarchive/Products/Applications/App.app" Payload/
codesign -s - --force --deep "Payload/App.app"
zip -r nestkeep.ipa Payload

echo ""
echo "=================================================="
echo " 完成: $(pwd)/nestkeep.ipa"
echo " 用 TrollStore 打开该 IPA 即可永久安装。"
echo "=================================================="
