#!/usr/bin/env bash
# 影随 / YingSui —— Android 发布密钥生成
#
# 用法：
#   ./scripts/create-android-keystore.sh
#   ./scripts/create-android-keystore.sh "自定义密码"
#
# 生成：
#   android/yingsui-release.jks   签名密钥库
#   android/key.properties        构建时读取的配置
#
# 重要警告（请务必读完）：
#   1. 这个密钥库一旦用于发布，**永久不能更换**。更换后老用户无法覆盖安装，
#      应用商店也无法更新（会被判定为「不同应用」）。
#   2. 请立刻把它备份到至少两个安全位置（如密码管理器 + 私有网盘）。
#      丢失密钥 = 无法再更新已发布的应用，只能换包名重新开始。
#   3. android/key.properties 与 *.jks 已在 .gitignore 中，
#      不要把密钥提交到任何公开仓库。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KEYSTORE="android/yingsui-release.jks"
KEY_ALIAS="yingsui"
PROPS="android/key.properties"

if [[ -f "$KEYSTORE" ]]; then
  echo "错误：$KEYSTORE 已存在。" >&2
  echo "      如果只是想重新生成，请先手动备份并删除它。" >&2
  echo "      注意：已发布应用更换密钥会导致无法更新。" >&2
  exit 1
fi

if [[ -x "$ROOT/../.toolchain/jdk-current/bin/keytool" ]]; then
  KEYTOOL="$ROOT/../.toolchain/jdk-current/bin/keytool"
elif command -v keytool >/dev/null 2>&1; then
  KEYTOOL="keytool"
else
  echo "错误：找不到 keytool。请先 source toolchain-env.sh，或安装 JDK。" >&2
  exit 1
fi

STORE_PASS="${1:-}"
if [[ -z "$STORE_PASS" ]]; then
  read -r -s -p "为密钥库设置一个强密码（记牢，丢失无法找回）: " STORE_PASS
  echo
  read -r -s -p "再输入一次确认: " STORE_PASS2
  echo
  [[ "$STORE_PASS" == "$STORE_PASS2" ]] || { echo "两次输入不一致。" >&2; exit 1; }
fi
[[ ${#STORE_PASS} -ge 8 ]] || { echo "密码至少 8 位。" >&2; exit 1; }

echo "==> 生成密钥库 $KEYSTORE"
"$KEYTOOL" -genkeypair \
  -v \
  -keystore "$KEYSTORE" \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -storepass "$STORE_PASS" \
  -keypass "$STORE_PASS" \
  -dname "CN=YingSui, OU=Mobile, O=YingSui, L=Unknown, ST=Unknown, C=CN"

echo "==> 写入 $PROPS"
cat > "$PROPS" <<EOF
storePassword=$STORE_PASS
keyPassword=$STORE_PASS
keyAlias=$KEY_ALIAS
# 注意：Gradle 的 file() 是相对 android/app 模块目录解析的，
# 因此必须用 ../ 指回 android/ 下的密钥库。
# 写成 android/xxx.jks 会变成 android/app/android/xxx.jks 而找不到文件。
storeFile=../$KEYSTORE
EOF

echo
echo "完成。下次执行以下命令即可产出正式签名包："
echo "  flutter build apk --release --flavor prod"
echo "  flutter build appbundle --release --flavor prod"
echo
echo "*** 请立刻备份 $KEYSTORE 与 $PROPS ***"
