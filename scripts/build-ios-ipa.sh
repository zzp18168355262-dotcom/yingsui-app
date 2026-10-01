#!/usr/bin/env bash
# 影随 / YingSui —— iOS 未签名 IPA 打包脚本
#
# 用途：
#   编译出未签名的 iOS 包，并打成标准 IPA。
#   这个 IPA 用于交给第三方签名服务（企业签/超级签）重签，
#   不需要 Apple 开发者账号。
#
# 用法：
#   ./scripts/build-ios-ipa.sh
#
# 产物：build/ios/ipa/YingSui-<版本>-unsigned.ipa

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/../toolchain-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/../toolchain-env.sh" >/dev/null 2>&1 || true
fi

cd "$ROOT"

VERSION="$(sed -nE 's/^version: ([^+]+).*/\1/p' pubspec.yaml)"
BUILD_NUMBER="$(sed -nE 's/^version: [^+]*\+([0-9]+).*/\1/p' pubspec.yaml)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> 编译 iOS（release，不签名）"
flutter build ios --release --no-codesign

APP="build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP" ]]; then
  echo "错误：未找到 $APP" >&2
  exit 1
fi

# ---- 嵌入 ffmpeg ----
# 与 macOS 同理：AI 字幕依赖内置音频组件做音频提取/分段。
# flutter build ios 不会自带，必须手动补，否则功能会报
# 「应用内置音频组件缺失或无法运行」。
FFMPEG_SRC="build/ffmpeg-bundle/ios-arm64/ffmpeg"
FFMPEG_DIR="$APP/ffmpeg"
if [[ -x "$FFMPEG_SRC" ]]; then
  echo "==> 嵌入 ffmpeg"
  mkdir -p "$FFMPEG_DIR"
  cp -a build/ffmpeg-bundle/ios-arm64/. "$FFMPEG_DIR/"
  chmod +x "$FFMPEG_DIR/ffmpeg"
else
  echo "==> 警告：未找到 $FFMPEG_SRC，AI 字幕在 iOS 上会失败。"
  echo "    iOS 版需要为 ios-arm64 目标编译 ffmpeg（在 macOS 上交叉编译）。"
fi

echo "==> 打包 IPA"
IPA_DIR="build/ios/ipa"
mkdir -p "$IPA_DIR"
PAYLOAD="$(mktemp -d)/Payload"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"

OUT="$IPA_DIR/YingSui-${VERSION}-unsigned.ipa"
rm -f "$OUT"
# 用 ditto 打包，保持 macOS 包结构（zip 会丢失部分元数据导致签名失败）
ditto -c -k --sequesterRsrc --keepParent "$PAYLOAD/Runner.app" "$OUT"

echo "==> 完成：$OUT"
echo
echo "下一步：把这个 IPA 交给签名服务商重签，或使用自己的开发者证书："
echo "  xcodebuild -exportArchive -archivePath <archive> -exportOptionsPlist <plist>"
echo
echo "提示：本机没有 Apple 开发者账号时不要执行 flutter build ipa，"
echo "      那条命令要求已配置签名身份。"
