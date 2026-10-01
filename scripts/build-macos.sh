#!/usr/bin/env bash
# 影随 / YingSui —— macOS 构建脚本
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
flutter build macos "--$MODE" || true

APP="$(find build/macos/Build/Products -maxdepth 2 -type d -name '*.app' -print -quit)"
if [[ -z "$APP" ]]; then
  echo "错误：未找到 .app 产物" >&2
  exit 1
fi
echo "==> 原始产物：$APP"

# 在 /tmp 下做干净拷贝，剥离扩展属性后再签名。
STAGE_APP="/tmp/YingSui-build-$$.app"
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
  OUT="build/macos/YingSui-${VERSION}.dmg"
  echo "==> 打包 DMG：$OUT"
  rm -rf build/macos/dmg-root "$OUT"
  mkdir -p build/macos/dmg-root
  cp -R "$FINAL" "build/macos/dmg-root/YingSui.app"
  ln -s /Applications build/macos/dmg-root/Applications
  hdiutil create -volname "影随 YingSui" \
    -srcfolder build/macos/dmg-root \
    -ov -format UDZO "$OUT"
  echo "==> 完成：$OUT"
fi

if [[ "$STAGE" == "stage" ]]; then
  mkdir -p dist
  rm -rf dist/YingSui.app
  cp -R "$FINAL" dist/YingSui.app
  echo "==> 已放到 dist/YingSui.app"
fi

echo "==> 完成：$FINAL"
echo "    启动：open \"$FINAL\""
