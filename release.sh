#!/usr/bin/env bash
#
# 英语角 / English Corner —— 版本号发布
#
# 用法：
#   ./release.sh v0.2.5
#
# 它做什么：
#   校验版本号递增 → 更新 pubspec.yaml 的 version → 本地提交并打 tag
#
# 它不做什么（刻意的）：
#   - 不推送到远端。本项目未配置 git remote，
#     原先的 `git push origin` 会在已删除的上游仓库上失败。
#   - 不构建分发包。构建请用：
#       ./scripts/build-all.sh          # 构建三平台
#       ./scripts/package-release.sh    # 汇总到 dist/
#
# 完整发版流程：./release.sh v0.2.5 && ./scripts/build-all.sh && ./scripts/package-release.sh

set -euo pipefail

# 加载本机工具链（Flutter/CocoaPods/JDK/Android SDK 都在仓库同级的 .toolchain 下）。
# 不加载的话 PATH 里没有 flutter，后续 analyze/test 会直接失败。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$ROOT/../toolchain-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/../toolchain-env.sh" >/dev/null 2>&1 || true
fi
cd "$ROOT"

die() {
  echo "Error: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || die "Usage: ./release.sh vMAJOR.MINOR.PATCH"

tag="$1"
tag="v${tag#v}"
version="${tag#v}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die "Version must be vMAJOR.MINOR.PATCH, for example v0.2.5."

[[ -f pubspec.yaml ]] || die "Run this script from the repository root."
[[ -z "$(git status --porcelain)" ]] || die "Working tree must be clean."

version_changed=false
committed=false
cleanup() {
  if [[ "$version_changed" == true && "$committed" == false ]]; then
    git restore -- pubspec.yaml
  fi
}
trap cleanup EXIT

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || die "Cannot release from a detached HEAD."

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "Local tag $tag already exists."
fi

current_version="$(sed -nE 's/^version: ([^[:space:]]+).*/\1/p' pubspec.yaml)"
[[ -n "$current_version" ]] || die "Cannot read the version from pubspec.yaml."
current_name="${current_version%%+*}"
current_build="${current_version#*+}"
[[ "$current_build" != "$current_version" ]] || current_build=0

IFS=. read -r current_major current_minor current_patch <<< "$current_name"
IFS=. read -r next_major next_minor next_patch <<< "$version"
if (( next_major < current_major ||
    (next_major == current_major && next_minor < current_minor) ||
    (next_major == current_major && next_minor == current_minor && next_patch <= current_patch) )); then
  die "Version $tag must be newer than v$current_name."
fi

next_build=$((current_build + 1))
next_version="$version+$next_build"

sed -i.bak -E "s/^version: .*/version: $next_version/" pubspec.yaml
rm pubspec.yaml.bak
version_changed=true

flutter_bin="flutter"
if ! command -v "$flutter_bin" >/dev/null 2>&1; then
  die "找不到 flutter。请先执行：source \$ROOT/../toolchain-env.sh"
fi

echo "==> 静态分析"
"$flutter_bin" analyze --no-pub
echo "==> 运行测试"
"$flutter_bin" test

git add pubspec.yaml
git commit -m "chore: release $tag"
committed=true
git tag "$tag"

echo
echo "已发布 $tag（应用版本 $next_version）"
echo
echo "下一步：构建并打包分发包"
echo "  ./scripts/build-all.sh"
echo "  ./scripts/package-release.sh"
