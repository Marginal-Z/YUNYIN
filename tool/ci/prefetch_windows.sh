#!/usr/bin/env bash
# Windows 构建前预先下载 media_kit 的 libmpv 压缩包（见 gh_release_download.sh），放到 CMake 查找的位置
# （build/windows/x64），用插件自带的 MD5 校验；一致时插件的 CMake 不再下载。在仓库根目录运行（Git Bash）。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cache=${PUB_CACHE:-$LOCALAPPDATA/Pub/Cache}
cache=$(cygpath -u "$cache" 2>/dev/null || echo "$cache")
cmake_file=$(find "$cache" -type f -path '*media_kit_libs_windows_audio-*/windows/CMakeLists.txt' | head -1)
name=$(sed -nE 's/^set\(LIBMPV "([^"]+)"\)/\1/p' "$cmake_file")
url=$(sed -nE 's/^set\(LIBMPV_URL "([^"]+)"\)/\1/p' "$cmake_file" | sed "s/\${LIBMPV}/$name/")
md5=$(sed -nE 's/^set\(LIBMPV_MD5 "([^"]+)"\)/\1/p' "$cmake_file")
dest="build/windows/x64/$name"
if [ ! -f "$dest" ] || [ "$(md5sum "$dest" | cut -d' ' -f1)" != "$md5" ]; then
  "$here/gh_release_download.sh" "$url" "$dest"
fi
if [ "$(md5sum "$dest" | cut -d' ' -f1)" != "$md5" ]; then
  echo "libmpv 校验失败：$dest" >&2
  rm -f "$dest"
  exit 1
fi
echo "libmpv 已校验：$dest"
