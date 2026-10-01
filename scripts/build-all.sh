#!/usr/bin/env bash
# 英语角 / English Corner —— 全平台构建
#
# 用法：
#   ./scripts/build-all.sh              # 构建 macOS + Android + iOS
#   ./scripts/build-all.sh macos        # 只构建指定平台
#   ./scripts/build-all.sh android ios
#
# 产物：
#   macOS    build/macos/Build/Products/<Config>/EnglishCorner.app（已 ad-hoc 签名）
#   Android  build/app/outputs/flutter-apk/app-prod-release.apk
#            build/app/outputs/bundle/prodRelease/app-prod-release.aab（供 Google Play）
#   iOS      build/ios/ipa/EnglishCorner-<版本>-unsigned.ipa（交签名服务重签）
#   Web      build/web（可选）
#
# 依赖：先执行 `source ../toolchain-env.sh` 或确保 PATH 里有 flutter / pod / java。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/../toolchain-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/../toolchain-env.sh" >/dev/null 2>&1 || true
fi
cd "$ROOT"

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=(macos android ios)
fi

VERSION="$(sed -nE 's/^version: ([^+]+).*/\1/p' pubspec.yaml)"

# ffmpeg 是 AI 字幕的必需组件：macOS/iOS 构建不会自动打包，缺了会报
# 「应用内置音频组件缺失或无法运行」。这里在构建前确保它已就绪。
ensure_ffmpeg() {
  local target="$1" dir="build/ffmpeg-bundle/$1"
  if [[ -x "$dir/ffmpeg" ]]; then
    echo "    ffmpeg 已就绪（${target}）"
    return
  fi
  echo "==> 编译 ffmpeg（${target}）"
  bash tool/ffmpeg/build_ffmpeg.sh "$target" "$dir"
}

summary=()

for t in "${TARGETS[@]}"; do
  case "$t" in
    macos)
      echo
      echo "========== macOS =========="
      ensure_ffmpeg macos-arm64
      ./scripts/build-macos.sh release
      summary+=("macOS    build/macos/Build/Products/Release/EnglishCorner.app")
      ;;
    android)
      echo
      echo "========== Android =========="
      if [[ ! -f android/key.properties ]]; then
        echo "    ! 未找到 android/key.properties，将使用 debug 签名。"
        echo "      正式发布请先运行：./scripts/create-android-keystore.sh"
      fi
      flutter build apk --release --flavor prod
      flutter build appbundle --release --flavor prod
      summary+=("Android  build/app/outputs/flutter-apk/app-prod-release.apk")
      summary+=("Android  build/app/outputs/bundle/prodRelease/app-prod-release.aab")
      ;;
    ios)
      echo
      echo "========== iOS =========="
      ensure_ffmpeg ios-arm64
      ./scripts/build-ios-ipa.sh
      summary+=("iOS      build/ios/ipa/EnglishCorner-${VERSION}-unsigned.ipa")
      ;;
    web)
      echo
      echo "========== Web =========="
      flutter build web --release
      summary+=("Web      build/web")
      ;;
    *)
      echo "未知平台：${t}（可选：macos android ios web）" >&2
      exit 1
      ;;
  esac
done

echo
echo "========== 构建完成 =========="
for line in "${summary[@]}"; do
  echo "  $line"
done
echo
echo "提醒："
echo "  - macOS 用户首次打开需右键→打开（未做 Apple 公证）"
echo "  - iOS 的 IPA 需交签名服务重签后才能安装"
echo "  - Android 若未配置正式密钥，产物无法上架商店"
