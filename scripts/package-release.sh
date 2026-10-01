#!/usr/bin/env bash
# 影随 / YingSui —— 发布打包
#
# 用途：
#   把已构建的三平台产物汇总到 dist/，生成 SHA256 校验文件与安装说明，
#   形成一个可以直接上传到服务器 / 网盘 / 应用商店的发布目录。
#
# 用法：
#   ./scripts/package-release.sh          # 汇总已有产物
#   ./scripts/package-release.sh --build  # 先构建再汇总（耗时较长）
#
# 产物结构：
#   dist/
#     YingSui-<版本>-macos.dmg             macOS 安装包
#     YingSui-<版本>-android.apk           Android 安装包
#     YingSui-<版本>-ios-unsigned.ipa      iOS（需签名服务重签）
#     SHA256SUMS.txt                       校验文件
#     安装说明.txt                          给最终用户的说明
#     manifest.json                        供更新接口使用

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/../toolchain-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/../toolchain-env.sh" >/dev/null 2>&1 || true
fi
cd "$ROOT"

DO_BUILD=false
[[ "${1:-}" == "--build" ]] && DO_BUILD=true

VERSION="$(sed -nE 's/^version: ([^+]+).*/\1/p' pubspec.yaml)"
BUILD_NO="$(sed -nE 's/^version: [^+]*\+([0-9]+).*/\1/p' pubspec.yaml)"
BUILD_NO="${BUILD_NO:-1}"
DIST="dist"

if [[ "$DO_BUILD" == true ]]; then
  echo "==> 先构建全部平台"
  ./scripts/build-all.sh macos android ios
fi

echo
echo "==> 汇总产物到 ${DIST}（版本 $VERSION+${BUILD_NO}）"
rm -rf "$DIST"
mkdir -p "$DIST"

copied=()

# ---- macOS ----
MAC_APP="build/macos/Build/Products/Release/YingSui.app"
if [[ -d "$MAC_APP" ]]; then
  DMG="$DIST/YingSui-${VERSION}-macos.dmg"
  echo "    打包 macOS DMG"
  rm -rf build/macos/dmg-root
  mkdir -p build/macos/dmg-root
  # 先做干净拷贝，避免 iCloud 扩展属性带进 DMG
  ditto --norsrc --noextattr "$MAC_APP" build/macos/dmg-root/YingSui.app
  ln -sf /Applications build/macos/dmg-root/Applications
  hdiutil create -volname "影随 YingSui" \
    -srcfolder build/macos/dmg-root -ov -format UDZO "$DMG" >/dev/null
  copied+=("$DMG")
else
  echo "    ! 跳过 macOS：未找到 $MAC_APP"
fi

# ---- Android ----
APK="build/app/outputs/flutter-apk/app-prod-release.apk"
if [[ -f "$APK" ]]; then
  cp "$APK" "$DIST/YingSui-${VERSION}-android.apk"
  copied+=("$DIST/YingSui-${VERSION}-android.apk")
else
  echo "    ! 跳过 Android：未找到 $APK"
fi

AAB="build/app/outputs/bundle/prodRelease/app-prod-release.aab"
if [[ -f "$AAB" ]]; then
  cp "$AAB" "$DIST/YingSui-${VERSION}-android.aab"
  echo "    （AAB 供 Google Play 上传，不分发给用户）"
fi

# ---- iOS ----
IPA="build/ios/ipa/YingSui-${VERSION}-unsigned.ipa"
if [[ -f "$IPA" ]]; then
  cp "$IPA" "$DIST/YingSui-${VERSION}-ios-unsigned.ipa"
  copied+=("$DIST/YingSui-${VERSION}-ios-unsigned.ipa")
else
  echo "    ! 跳过 iOS：未找到 $IPA"
fi

if [[ ${#copied[@]} -eq 0 ]]; then
  echo "错误：没有找到任何可发布的产物。请先构建。" >&2
  exit 1
fi

# ---- SHA256 校验文件 ----
# 应用内的更新检查会寻找 SHA256SUMS.txt，命名与格式需保持一致。
echo
echo "==> 生成 SHA256SUMS.txt"
(
  cd "$DIST"
  shasum -a 256 ./*.dmg ./*.apk ./*.ipa 2>/dev/null > SHA256SUMS.txt || true
)
cat "$DIST/SHA256SUMS.txt" | sed 's/^/    /'

# ---- manifest.json（供自有更新接口使用）----
echo
echo "==> 生成 manifest.json"
python3 - "$DIST" "$VERSION" "$BUILD_NO" <<'PY'
import hashlib, json, os, sys

dist, version, build_no = sys.argv[1], sys.argv[2], int(sys.argv[3])
assets = []
for name in sorted(os.listdir(dist)):
    if not name.lower().endswith((".dmg", ".apk", ".ipa", ".zip")):
        continue
    path = os.path.join(dist, name)
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    platform = "macos" if name.endswith(".dmg") else (
        "ios" if name.endswith(".ipa") else "android")
    assets.append({
        "name": name,
        "platform": platform,
        "size": os.path.getsize(path),
        "sha256": h.hexdigest(),
        "downloadUrl": f"/downloads/{name}",
    })

manifest = {
    "version": version,
    "buildNumber": build_no,
    "assets": assets,
    "checksumUrl": "/downloads/SHA256SUMS.txt",
    "releaseNotesUrl": "/downloads/release-notes.txt",
}
with open(os.path.join(dist, "manifest.json"), "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=2)
print(f"    写入 {len(assets)} 个条目")
PY

# ---- 安装说明 ----
echo
echo "==> 生成安装说明.txt"
cat > "$DIST/安装说明.txt" <<EOF
影随 YingSui  ${VERSION}（构建 ${BUILD_NO}）

感谢使用。请按你的设备选择对应文件：

────────────────────────────────
Windows
────────────────────────────────
暂未提供。请使用 Android 或 macOS 版。


────────────────────────────────
Android 手机 / 平板
────────────────────────────────
文件：YingSui-${VERSION}-android.apk

安装步骤：
  1. 把 apk 传到手机上（微信/QQ/数据线均可）
  2. 点击安装。系统可能提示「未知来源」，选择允许即可
     （路径：设置 → 安全 → 允许安装未知应用）
  3. 首次打开跟读功能时，请允许「录音」权限

若提示「应用未安装」，请先卸载旧版本再装。


────────────────────────────────
macOS 电脑
────────────────────────────────
文件：YingSui-${VERSION}-macos.dmg

安装步骤：
  1. 双击 dmg，把「影随」拖进「应用程序」
  2. 首次打开会提示「无法验证开发者」—— 这是正常的
     （本应用未做 Apple 公证）
  3. 解决办法（任选其一）：
     · 右键点击图标 → 选择「打开」→ 再点「打开」
     · 或：系统设置 → 隐私与安全性 → 找到影随 → 点「仍要打开」
  4. 首次使用跟读功能时，请允许「麦克风」权限


────────────────────────────────
iPhone / iPad
────────────────────────────────
文件：YingSui-${VERSION}-ios-unsigned.ipa

此文件需要签名后才能安装，请按提供的安装指引操作。


────────────────────────────────
常见问题
────────────────────────────────
Q：AI 字幕生成失败？
A：请在「设置 → 翻译」里填写自己的 API Key。
   本应用不内置密钥，需要你自行申请第三方语音识别服务。

Q：跟读录不到声音？
A：请在系统设置里允许本应用的「麦克风」权限。

Q：跟读录音保存在哪？
A：只保存在你的设备本地，不会上传。

────────────────────────────────
文件校验（可选）
────────────────────────────────
如需确认下载文件完整，可比对 SHA256SUMS.txt 中的值：
  macOS/Linux:  shasum -a 256 <文件名>
  Windows:      certutil -hashfile <文件名> SHA256
EOF

echo
echo "========== 发布目录就绪 =========="
ls -lh "$DIST" | tail -n +2 | awk '{printf "  %-42s %s\n", $9, $5}'
echo
echo "下一步：把 dist/ 整个目录上传到你的服务器或网盘。"
