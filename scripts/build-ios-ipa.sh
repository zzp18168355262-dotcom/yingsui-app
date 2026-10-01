#!/usr/bin/env bash
# 英语角 / English Corner —— iOS 未签名 IPA 打包脚本
#
# 用途：
#   编译出未签名的 iOS 包并打成标准 IPA，交给第三方签名服务重签
#   （企业签/超级签），不需要 Apple 开发者账号。
#
# 用法：
#   ./scripts/build-ios-ipa.sh
#
# 产物：build/ios/ipa/EnglishCorner-<版本>-unsigned.ipa
#
# 实现说明（为什么不用 flutter build ios）：
#   Flutter 3.44 的 `flutter build ios` 在解析 Swift Package Manager
#   依赖时会以仓库根目录作为工作目录调用
#   `xcodebuild -resolvePackageDependencies`，Xcode 会报
#   "does not contain an Xcode project, workspace or package" 而失败。
#   直接调用 xcodebuild 构建 Runner.xcworkspace 可行且已实测通过，
#   因此这里采用直接构建，并把 DerivedData 固定在工作区内。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/../toolchain-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/../toolchain-env.sh" >/dev/null 2>&1 || true
fi

cd "$ROOT"

VERSION="$(sed -nE 's/^version: ([^+]+).*/\1/p' pubspec.yaml)"
SCHEME="${IOS_SCHEME:-Runner}"
CONFIGURATION="${IOS_CONFIGURATION:-Release}"
CONFIG_LOWER="$(echo "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"

echo "==> 准备 Flutter 侧产物（Dart 编译 / flutter_assets）"
# flutter build ios 的失败点只在最后的 SPM 解析；在此之前它已经产出了
# App.framework 与 flutter_assets，因此这里忽略退出码。
flutter build ios "--$CONFIG_LOWER" --no-codesign >/dev/null 2>&1 || true

echo "==> 安装 Pods"
(cd ios && pod install >/dev/null)

# DerivedData 必须放在 /tmp，不能放工作区内。
# 原因：仓库位于 iCloud 托管目录（~/Documents）时，iCloud 会给中间产物
# 贴上 com.apple.FinderInfo 扩展属性；构建过程中对嵌套 framework
# （如 native_assets/objective_c.framework）签名时报
#   resource fork, Finder information, or similar detritus not allowed
# 而失败。放到 /tmp 可彻底避开。
DERIVED_TMP="/tmp/EnglishCorner-ios-dd"

echo "==> xcodebuild ($CONFIGURATION / $SCHEME)"
(
  cd ios
  xcodebuild \
    -workspace Runner.xcworkspace \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_TMP" \
    CODE_SIGNING_ALLOWED=NO \
    build
)

APP="$DERIVED_TMP/Build/Products/${CONFIGURATION}-iphoneos/Runner.app"
if [[ ! -d "$APP" ]]; then
  echo "错误：未找到 $APP" >&2
  ls -1 "$DERIVED_TMP/Build/Products/" 2>/dev/null >&2 || true
  exit 1
fi
echo "==> 产物：$APP"

# ---- 嵌入 ffmpeg ----
# AI 字幕依赖内置音频组件做音频提取与分段；flutter build 不会自带，
# 缺少时应用内会报「应用内置音频组件缺失或无法运行」。
FFMPEG_SRC="build/ffmpeg-bundle/ios-arm64/ffmpeg"
if [[ -x "$FFMPEG_SRC" ]]; then
  echo "==> 嵌入 ffmpeg"
  mkdir -p "$APP/ffmpeg"
  cp -a build/ffmpeg-bundle/ios-arm64/. "$APP/ffmpeg/"
  chmod +x "$APP/ffmpeg/ffmpeg"
else
  echo "==> 警告：未找到 ${FFMPEG_SRC}，iOS 上 AI 字幕会失败。"
  echo "    先执行：bash tool/ffmpeg/build_ffmpeg.sh ios-arm64 build/ffmpeg-bundle/ios-arm64"
fi

echo "==> 打包 IPA"
IPA_DIR="build/ios/ipa"
mkdir -p "$IPA_DIR"
STAGE="$(mktemp -d)"
PAYLOAD="$STAGE/Payload"
mkdir -p "$PAYLOAD"
ditto --norsrc --noextattr "$APP" "$PAYLOAD/Runner.app"

OUT="$IPA_DIR/EnglishCorner-${VERSION}-unsigned.ipa"
rm -f "$OUT"
(cd "$STAGE" && zip -qry "$ROOT/$OUT" Payload)
rm -rf "$STAGE"

echo "==> 完成：$OUT"
echo
echo "下一步：交给签名服务商重签，或用自己的开发者证书导出："
echo "  xcodebuild -exportArchive -archivePath <archive> -exportOptionsPlist <plist>"
