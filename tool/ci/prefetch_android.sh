#!/usr/bin/env bash
# Android 构建前预先下载 Gradle 与 media_kit 的 libmpv 安卓库（见 gh_release_download.sh），并校验：
# - Gradle：用 Gradle 官网公布的 SHA-256 校验，然后让 Gradle 包装器使用这个本地文件；
# - libmpv：放到 media_kit 构建时查找的位置，用插件自带的 MD5 校验（一致时插件不再下载）。
# 在仓库根目录、flutter pub get 之后运行。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fetch="$here/gh_release_download.sh"

# 1. Gradle
props=android/gradle/wrapper/gradle-wrapper.properties
dist_url=$(sed -n 's/^distributionUrl=//p' "$props" | sed 's/\\:/:/g')
zip=$(basename "$dist_url")
version=$(echo "$zip" | sed -E 's/^gradle-(.+)-(all|bin)\.zip$/\1/')
# 放在 ~/.gradle/wrapper 下，随 setup-java 的 Gradle 缓存一起保存。
local_zip="$HOME/.gradle/wrapper/yunyin/$zip"
sha=$(curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 "https://downloads.gradle.org/distributions/$zip.sha256")
if [ ! -f "$local_zip" ] || [ "$(sha256sum "$local_zip" | cut -d' ' -f1)" != "$sha" ]; then
  "$fetch" "https://github.com/gradle/gradle-distributions/releases/download/v$version/$zip" "$local_zip"
fi
actual=$(sha256sum "$local_zip" | cut -d' ' -f1)
if [ "$actual" != "$sha" ]; then
  echo "Gradle 校验失败：期望 $sha，实际 $actual" >&2
  rm -f "$local_zip"
  exit 1
fi
sed -i "s#^distributionUrl=.*#distributionUrl=file\\\\://$local_zip#" "$props"
echo "Gradle $version 已校验：$local_zip"

# 2. libmpv 安卓库
gradle_file=$(find "${PUB_CACHE:-$HOME/.pub-cache}" -type f -path '*media_kit_libs_android_audio-*/android/build.gradle' | head -1)
grep -oE '"url": "https://github.com/media-kit/[^"]+\.jar", "md5": "[0-9a-f]{32}"' "$gradle_file" | while read -r line; do
  url=$(echo "$line" | sed -E 's/.*"url": "([^"]+)".*/\1/')
  md5=$(echo "$line" | sed -E 's/.*"md5": "([^"]+)".*/\1/')
  dest="build/media_kit_libs_android_audio/$(echo "$url" | cut -d/ -f8)/$(basename "$url")"
  if [ ! -f "$dest" ] || [ "$(md5sum "$dest" | cut -d' ' -f1)" != "$md5" ]; then
    "$fetch" "$url" "$dest"
  fi
  if [ "$(md5sum "$dest" | cut -d' ' -f1)" != "$md5" ]; then
    echo "libmpv 校验失败：$dest" >&2
    rm -f "$dest"
    exit 1
  fi
  echo "libmpv 已校验：$dest"
done
