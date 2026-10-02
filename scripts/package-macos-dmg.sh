#!/usr/bin/env bash
# 把已构建的 macOS 应用打成可分发的 DMG。
#
# 用法：./scripts/package-macos-dmg.sh [版本号]
#   版本号缺省时从 pubspec.yaml 读取。
#
# 为什么要绕这一圈（几个踩过的坑）：
#   1. 仓库位于 ~/Documents（iCloud 同步目录）。iCloud 会给文件附加
#      扩展属性，导致 codesign 校验失败、应用启动报
#      「code object is not signed at all」。因此签名与打包都在
#      /tmp 下进行，最后只把 DMG 拷回 dist/。
#   2. hdiutil 在 iCloud 目录下直接建 DMG 会失败（目录非空）。
#   3. 未购买 Apple 开发者证书，只能做 ad-hoc 签名（codesign -s -）。
#      因此包内附「安装说明.txt」，说明首次打开的放行方式。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(grep -E '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)}"
APP_NAME="EnglishCorner"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
VOL_NAME="英语角 English Corner"
STAGE="/tmp/ec-dmg-stage"
DMG_OUT="/tmp/${APP_NAME}-${VERSION}-macos.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "找不到已构建的应用：$APP_PATH" >&2
  echo "请先执行：./scripts/build-macos.sh release" >&2
  exit 1
fi

echo "==> 版本：$VERSION"

# 1) 在 /tmp 下重新签名（避开 iCloud 扩展属性的干扰）
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto --norsrc --noextattr "$APP_PATH" "$STAGE/${APP_NAME}.app"
codesign --force --deep --sign - "$STAGE/${APP_NAME}.app"
codesign --verify --deep --strict "$STAGE/${APP_NAME}.app"
echo "    签名完成（ad-hoc）并校验通过"

# 2) 组装 DMG 内容：应用 + 指向「应用程序」的快捷方式 + 安装说明
ln -sfn /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<EOF
英语角 English Corner  v${VERSION}
================================

【安装】
把左边的 ${APP_NAME} 拖到右边的 Applications 文件夹即可。

【首次打开会被 macOS 拦一下（重要）】
本应用没有购买 Apple 开发者签名（\$99/年），所以系统无法验证它的来源。
首次打开请任选一种方式：

  方式一（推荐）
    在「应用程序」里找到 ${APP_NAME}，
    按住 Control 键点它（或右键）→ 选择「打开」→ 再点「打开」。

  方式二
    双击后被拦 → 打开「系统设置」→「隐私与安全性」→
    在「安全性」区域点「仍要打开」。

  方式三（上面都不行时）
    打开「终端」执行：
      xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app

放行一次之后，以后双击就能正常打开。

【说明】
- 视频和字幕都用你自己的本地文件，本软件不联网上传。
- 若要做口播/听写练习，麦克风权限会在首次使用时询问。
EOF

# 3) 生成 DMG（在 /tmp 下进行）
rm -f "$DMG_OUT"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_OUT" >/dev/null
echo "    已生成：$DMG_OUT"

# 4) 校验：挂载一次，确认卷内应用可读、版本正确
MOUNT_POINT="$(hdiutil attach "$DMG_OUT" -nobrowse | awk '/\/Volumes\//{print substr($0, index($0,"/Volumes/"))}' | tail -1)"
if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
  IN_DMG_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT_POINT/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo '?')"
  echo "    卷内应用版本：$IN_DMG_VERSION"
  hdiutil detach "$MOUNT_POINT" >/dev/null
fi

# 5) 归档到 dist/，并更新校验文件
mkdir -p dist
cp "$DMG_OUT" "dist/${APP_NAME}-${VERSION}-macos.dmg"
cd dist
shasum -a 256 "${APP_NAME}-${VERSION}-macos.dmg" > SHA256SUMS.txt
echo "==> 完成：dist/${APP_NAME}-${VERSION}-macos.dmg"
echo "    $(cat SHA256SUMS.txt)"
