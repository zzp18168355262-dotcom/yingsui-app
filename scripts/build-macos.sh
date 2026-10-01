#!/usr/bin/env bash
# 英语角 / English Corner —— macOS 构建脚本
#
# 用法：
#   ./scripts/build-macos.sh              # debug 构建
#   ./scripts/build-macos.sh release      # release 构建
#   ./scripts/build-macos.sh release dmg  # release + 打包 DMG
#   ./scripts/build-macos.sh release dmg stage   # 额外把产物放到 dist/
#
# 背景说明（这份脚本为什么这么做）：
# 1) 本机 Flutter 工具链装在仓库的 .toolchain 下，需要通过 toolchain-env.sh 加载。
# 2) 如果仓库放在 iCloud 托管的目录（如 ~/Documents）下，文件系统会给产物
#    贴上 com.apple.FinderInfo 扩展属性，codesign 会以
#      "resource fork, Finder information, or similar detritus not allowed"
#    失败。因此签名阶段在 /tmp 下做干净拷贝再签，签完可正常启动。
#    在普通（非 iCloud）目录下不会有这个问题。

set -euo pipefail

MODE="${1:-debug}"
PACKAGE_DMG="${2:-}"
STAGE="${3:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/../toolchain-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/../toolchain-env.sh" >/dev/null 2>&1 || true
fi

cd "$ROOT"

echo "==> 构建 macOS ($MODE)"
# flutter build macos 不支持 --no-codesign（那是 iOS 的参数）。
# 它自带的签名会因为目录受 iCloud 影响而失败，这没关系：
# 我们随后会在 /tmp 做干净拷贝统一重新签名。
flutter build macos "--$MODE" || true

# 明确指定产物路径。不要用 find 通配 —— 构建目录里可能残留
# 历史的 *.app（例如测试用的 EnglishCorner-signed.app），会被误选。
case "$MODE" in
  debug) CONFIG_DIR="Debug" ;;
  profile) CONFIG_DIR="Profile" ;;
  release) CONFIG_DIR="Release" ;;
  *) CONFIG_DIR="Debug" ;;
esac
APP="build/macos/Build/Products/$CONFIG_DIR/EnglishCorner.app"
if [[ ! -d "$APP" ]]; then
  echo "错误：未找到 $APP" >&2
  echo "构建目录现状：" >&2
  ls -1 "build/macos/Build/Products/" 2>/dev/null >&2 || true
  exit 1
fi
echo "==> 原始产物：$APP"

# ---- 嵌入 ffmpeg ----
# 应用在 macOS 上按 Contents/Resources/ffmpeg/ffmpeg 查找内置音频组件；
# 没有它，AI 字幕会报「应用内置音频组件缺失或无法运行」。
# flutter build macos 不会自动带上它，必须在这里补。
FFMPEG_SRC="build/ffmpeg-bundle/macos-arm64/ffmpeg"
FFMPEG_DIR="$APP/Contents/Resources/ffmpeg"
if [[ -x "$FFMPEG_SRC" ]]; then
  echo "==> 嵌入 ffmpeg"
  mkdir -p "$FFMPEG_DIR"
  cp -a build/ffmpeg-bundle/macos-arm64/. "$FFMPEG_DIR/"
  chmod +x "$FFMPEG_DIR/ffmpeg"
  "$FFMPEG_DIR/ffmpeg" -version >/dev/null 2>&1 \
    && echo "    ffmpeg 可运行" \
    || echo "    警告：ffmpeg 无法运行，AI 字幕仍会失败"
else
  echo "==> 警告：未找到 $FFMPEG_SRC"
  echo "    请先执行：bash tool/ffmpeg/build_ffmpeg.sh macos-arm64 build/ffmpeg-bundle/macos-arm64"
  echo "    否则应用内的 AI 字幕功能会因为缺少音频组件而失败。"
fi

# 在 /tmp 下做干净拷贝，剥离扩展属性后再签名。
STAGE_APP="/tmp/EnglishCorner-build-$$.app"
rm -rf "$STAGE_APP"
echo "==> 干净拷贝到 $STAGE_APP"
ditto --norsrc --noextattr "$APP" "$STAGE_APP"

echo "==> 签名（ad-hoc）"
codesign --force --deep --sign - "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP" && echo "    签名校验通过"

FINAL="$APP"
if codesign --force --deep --sign - "$APP" 2>/dev/null; then
  echo "==> 原件也已签名（当前目录未受 iCloud 影响）"
else
  echo "==> 原件所在目录受 iCloud 影响，使用 /tmp 下的已签名产物"
  FINAL="$STAGE_APP"
fi

if [[ "$PACKAGE_DMG" == "dmg" ]]; then
  VERSION="$(sed -nE 's/^version: ([^+]+).*/\1/p' pubspec.yaml)"
  OUT="build/macos/EnglishCorner-${VERSION}.dmg"
  echo "==> 打包 DMG：$OUT"
  rm -rf build/macos/dmg-root "$OUT"
  mkdir -p build/macos/dmg-root
  cp -R "$FINAL" "build/macos/dmg-root/EnglishCorner.app"
  ln -s /Applications build/macos/dmg-root/Applications
  hdiutil create -volname "英语角 English Corner" \
    -srcfolder build/macos/dmg-root \
    -ov -format UDZO "$OUT"
  echo "==> 完成：$OUT"
fi

if [[ "$STAGE" == "stage" ]]; then
  mkdir -p dist
  rm -rf dist/EnglishCorner.app
  cp -R "$FINAL" dist/EnglishCorner.app
  echo "==> 已放到 dist/EnglishCorner.app"
fi

echo "==> 完成：$FINAL"
echo "    启动：open \"$FINAL\""
