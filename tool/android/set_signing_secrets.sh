#!/usr/bin/env bash
# 把 Android 发布密钥写入 GitHub Actions secrets，CI 用它签名所有发布的 APK。
# 签名固定后，新版本才能覆盖安装旧版本。请同时备份 android/key.properties 与 android/app/yunyin-release.keystore。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${1:-Marginal-Z/YUNYIN}"
KEYSTORE="$ROOT/android/app/yunyin-release.keystore"
test -f "$KEYSTORE" || { echo "找不到 $KEYSTORE"; exit 1; }
base64 -w0 "$KEYSTORE" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$REPO"
grep '^storePassword=' "$ROOT/android/key.properties" | cut -d= -f2- | tr -d '\n' | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO"
gh secret list --repo "$REPO"
