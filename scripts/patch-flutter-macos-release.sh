#!/usr/bin/env bash
# 影随 / YingSui —— 给 Flutter 打补丁：修复 macOS release 构建
#
# 背景：
#   Flutter 3.44.4 的 flutter_tools 在打包 macOS framework 时执行：
#     lipo <framework> -verify_arch x86_64 arm64
#   但 `lipo -verify_arch` 一次只接受**一个**架构参数，
#   传多个会被当成「额外输入文件」，报
#     lipo: -verify_arch requires exactly one input file
#   并返回非零退出码。于是 macOS release 构建必然失败：
#     Binary .../FlutterMacOS does not contain architectures "x86_64 arm64"
#
#   注意：无论 framework 是单架构还是双架构都会失败 ——
#   问题出在参数个数（>1），而不是架构本身。
#   debug 构建恰好只传一个架构（arm64），所以能过。
#
# 本脚本做的事：
#   1. 把 flutter_tools 里的架构校验改为逐个验证（幂等，已打过会跳过）
#   2. 删除 flutter_tools 快照与 stamp，并按官方方式重新生成快照
#
# 用法：
#   ./scripts/patch-flutter-macos-release.sh
#
# 何时需要重跑：
#   Flutter 升级或 `flutter upgrade` 之后（快照会被重新生成，覆盖补丁）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="$ROOT/tool/patches/flutter-lipo-verify-arch.patch"

FLUTTER_ROOT="${FLUTTER_ROOT:-}"
if [[ -z "$FLUTTER_ROOT" ]]; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_ROOT="$(cd "$(dirname "$(command -v flutter)")/.." && pwd)"
  else
    echo "错误：找不到 Flutter。请先 source toolchain-env.sh" >&2
    exit 1
  fi
fi

TARGET="$FLUTTER_ROOT/packages/flutter_tools/lib/src/build_system/targets/darwin.dart"
SNAPSHOT="$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot"
STAMP="$FLUTTER_ROOT/bin/cache/flutter_tools.stamp"
DART="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"

[[ -f "$TARGET" ]] || { echo "错误：找不到 $TARGET" >&2; exit 1; }
[[ -f "$PATCH_FILE" ]] || { echo "错误：找不到 $PATCH_FILE" >&2; exit 1; }

echo "Flutter: $FLUTTER_ROOT"

if grep -q "逐个验证" "$TARGET"; then
  echo "==> 源码已打过补丁，跳过"
else
  echo "==> 应用补丁到 darwin.dart"
  # 优先用 git apply（能识别上下文）；失败则用 patch -p1
  if command -v git >/dev/null 2>&1 &&
     (cd "$FLUTTER_ROOT" && git apply --check "$PATCH_FILE" 2>/dev/null); then
    (cd "$FLUTTER_ROOT" && git apply "$PATCH_FILE")
  else
    (cd "$FLUTTER_ROOT" && patch -p1 < "$PATCH_FILE")
  fi
  echo "    已应用"
fi

if [[ ! -x "$DART" ]]; then
  echo "错误：找不到 Dart SDK：$DART" >&2
  exit 1
fi

echo "==> 重新生成 flutter_tools 快照"
# 快照只在 revision 变化时才重建，改了源码不会自动生效，必须手动重建。
[[ -f "$SNAPSHOT" ]] && cp "$SNAPSHOT" "$SNAPSHOT.bak"
rm -f "$SNAPSHOT" "$STAMP"
"$DART" --verbosity=error \
  --snapshot="$SNAPSHOT" \
  --snapshot-kind="app-jit" \
  --packages="$FLUTTER_ROOT/packages/flutter_tools/.dart_tool/package_config.json" \
  --no-enable-mirrors \
  "$FLUTTER_ROOT/packages/flutter_tools/bin/flutter_tools.dart" \
  >/dev/null

echo "    快照已重建（$(du -h "$SNAPSHOT" | cut -f1)）"
echo
echo "完成。现在 macOS release 构建可正常进行："
echo "  ./scripts/build-macos.sh release"
