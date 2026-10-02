#!/usr/bin/env bash
# 英语角 / English Corner —— 发布打包
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
#     EnglishCorner-<版本>-macos.zip             macOS 安装包
#     EnglishCorner-<版本>-android.apk           Android 安装包
#     EnglishCorner-<版本>-ios-unsigned.ipa      iOS（需签名服务重签）
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
# 产出 ZIP：用户解压后把 .app 拖进「应用程序」即可。
#
# 为什么要在 /tmp 里签名再打包：
#   仓库位于 iCloud 托管目录（~/Documents）时，文件系统会持续给 .app 贴上
#   com.apple.FinderInfo 扩展属性，导致 codesign 报
#     "resource fork, Finder information, or similar detritus not allowed"
#   并且写入工作区的包无法通过签名校验。结果是：ZIP 里的 app 未签名，
#   用户解压后双击直接报 Launch failed / code object is not signed at all。
#
#   因此流程是：工作区产物 → ditto 干净拷贝到 /tmp → 在 /tmp 签名
#   （签名后不再被贴属性）→ 就地打包 ZIP → ZIP 拷回 dist。
MAC_APP="build/macos/Build/Products/Release/EnglishCorner.app"
if [[ -d "$MAC_APP" ]]; then
  MAC_ZIP="$DIST/EnglishCorner-${VERSION}-macos.zip"
  STAGE_DIR="$(mktemp -d /tmp/EnglishCorner-pkg-XXXXXX)"
  STAGE_APP="$STAGE_DIR/EnglishCorner.app"

  echo "    准备 macOS 包（干净拷贝到 /tmp 后签名）"
  ditto --norsrc --noextattr "$MAC_APP" "$STAGE_APP"

  if codesign --force --deep --sign - "$STAGE_APP" 2>/dev/null &&
     codesign --verify --deep --strict "$STAGE_APP" 2>/dev/null; then
    echo "      签名校验通过"
  else
    echo "      ! 警告：签名校验未通过，产出的 app 可能无法直接打开"
  fi

  echo "    打包 macOS ZIP"
  rm -f "$MAC_ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$STAGE_APP" "$MAC_ZIP"
  copied+=("$MAC_ZIP")

  if [[ "${MAKE_DMG:-0}" == "1" ]]; then
    DMG="$DIST/EnglishCorner-${VERSION}-macos.dmg"
    echo "    尝试打包 macOS DMG"
    rm -rf build/macos/dmg-root
    mkdir -p build/macos/dmg-root
    ditto "$STAGE_APP" build/macos/dmg-root/EnglishCorner.app
    ln -sf /Applications build/macos/dmg-root/Applications
    if hdiutil create -volname "英语角 English Corner" \
        -srcfolder build/macos/dmg-root -ov -format UDZO "$DMG" >/dev/null 2>&1; then
      copied+=("$DMG")
      echo "      DMG 打包成功"
    else
      echo "      ! DMG 打包失败（当前环境不支持 hdiutil），已跳过。ZIP 可正常使用。"
      rm -f "$DMG"
    fi
  fi

  rm -rf "$STAGE_DIR"
else
  echo "    ! 跳过 macOS：未找到 $MAC_APP"
fi

# ---- Android ----
APK="build/app/outputs/flutter-apk/app-prod-release.apk"
if [[ -f "$APK" ]]; then
  cp "$APK" "$DIST/EnglishCorner-${VERSION}-android.apk"
  copied+=("$DIST/EnglishCorner-${VERSION}-android.apk")
else
  echo "    ! 跳过 Android：未找到 $APK"
fi

AAB="build/app/outputs/bundle/prodRelease/app-prod-release.aab"
if [[ -f "$AAB" ]]; then
  cp "$AAB" "$DIST/EnglishCorner-${VERSION}-android.aab"
  echo "    （AAB 供 Google Play 上传，不分发给用户）"
fi

# ---- iOS ----
IPA="build/ios/ipa/EnglishCorner-${VERSION}-unsigned.ipa"
if [[ -f "$IPA" ]]; then
  cp "$IPA" "$DIST/EnglishCorner-${VERSION}-ios-unsigned.ipa"
  copied+=("$DIST/EnglishCorner-${VERSION}-ios-unsigned.ipa")
else
  echo "    ! 跳过 iOS：未找到 $IPA"
fi

if [[ ${#copied[@]} -eq 0 ]]; then
  echo "错误：没有找到任何可发布的产物。请先构建。" >&2
  exit 1
fi

# ---- SHA256 校验文件 ----
# 应用内的更新检查会寻找 SHA256SUMS.txt，命名与格式需保持一致。
# 注意要覆盖所有分发包格式（zip/dmg/apk/ipa），否则会漏掉校验项。
echo
echo "==> 生成 SHA256SUMS.txt"
(
  cd "$DIST"
  found=0
  for f in ./*.zip ./*.dmg ./*.apk ./*.ipa; do
    [[ -f "$f" ]] || continue
    shasum -a 256 "$f"
    found=1
  done > SHA256SUMS.txt
  [[ "$found" == "1" ]] || echo "（没有可分发的文件）" > SHA256SUMS.txt
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
    # 注意：macOS 分发包是 .zip（DMG 在当前环境不可用），
    # 只判断 .dmg 会把 macOS 包误标成 android，导致检查更新时推错包。
    if name.endswith((".zip", ".dmg")):
        platform = "macos"
    elif name.endswith(".ipa"):
        platform = "ios"
    else:
        platform = "android"
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
英语角 English Corner  ${VERSION}（构建 ${BUILD_NO}）

感谢使用。请按你的设备选择对应文件：

────────────────────────────────
Windows
────────────────────────────────
暂未提供。请使用 Android 或 macOS 版。


────────────────────────────────
Android 手机 / 平板
────────────────────────────────
文件：EnglishCorner-${VERSION}-android.apk

安装步骤：
  1. 把 apk 传到手机上（微信/QQ/数据线均可）
  2. 点击安装。系统可能提示「未知来源」，选择允许即可
     （路径：设置 → 安全 → 允许安装未知应用）
  3. 首次打开跟读功能时，请允许「录音」权限

若提示「应用未安装」，请先卸载旧版本再装。


────────────────────────────────
macOS 电脑
────────────────────────────────
文件：EnglishCorner-${VERSION}-macos.zip

安装步骤：
  1. 双击 zip 解压，把「英语角」拖进「应用程序」
  2. 首次打开会提示「无法验证开发者」—— 这是正常的
     （本应用未做 Apple 公证）
  3. 解决办法（任选其一）：
     · 右键点击图标 → 选择「打开」→ 再点「打开」
     · 或：系统设置 → 隐私与安全性 → 找到英语角 → 点「仍要打开」
  4. 首次使用跟读功能时，请允许「麦克风」权限


────────────────────────────────
iPhone / iPad
────────────────────────────────
文件：EnglishCorner-${VERSION}-ios-unsigned.ipa

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

# ---- 更新说明 ----
# manifest.json 里的 releaseNotesUrl 指向它。
# 不生成的话，用户点「查看更新说明」会 404。
echo
echo "==> 生成 release-notes.txt"
cat > "$DIST/release-notes.txt" <<EOF
英语角 English Corner ${VERSION} (build ${BUILD_NO})

下载文件 / Downloads
  macOS               EnglishCorner-${VERSION}-macos.zip
  Android             EnglishCorner-${VERSION}-android.apk
  Android (Play)      EnglishCorner-${VERSION}-android.aab
  iOS (需签名)         EnglishCorner-${VERSION}-ios-unsigned.ipa

安装说明见 安装说明.txt。
Windows 版暂未提供。

English Corner ${VERSION} (build ${BUILD_NO})
See 安装说明.txt for installation steps.
Windows build is not available yet.
EOF

echo
echo "========== 发布目录就绪 =========="
ls -lh "$DIST" | tail -n +2 | awk '{printf "  %-42s %s\n", $9, $5}'
echo
echo "下一步：把 dist/ 整个目录上传到你的服务器或网盘。"
