#!/usr/bin/env bash
# 打包 Linux 发行版：生成 .deb（依赖系统 libmpv）以及附带 libmpv 的便携 tar.gz 与 AppImage。
# 用法：tool/linux/package.sh <版本号>（在 flutter build linux --release 之后运行）
set -euo pipefail

VERSION="${1:?需要版本号}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACHINE="$(uname -m)"                       # x86_64 / aarch64
case "$MACHINE" in
  x86_64) ARCH=x64; DEB_ARCH=amd64 ;;
  aarch64) ARCH=arm64; DEB_ARCH=arm64 ;;
  *) echo "不支持的架构：$MACHINE"; exit 1 ;;
esac
BUNDLE="$ROOT/build/linux/$ARCH/release/bundle"
DIST="$ROOT/dist"
WORK="$(mktemp -d)"
mkdir -p "$DIST"
test -x "$BUNDLE/yunyin" || { echo "找不到 $BUNDLE/yunyin，请先 flutter build linux --release"; exit 1; }

fetch() { # 下载 AppImage 工具
  curl -fsSL -o "$WORK/$1" "$2"
  chmod +x "$WORK/$1"
}
export APPIMAGE_EXTRACT_AND_RUN=1

# 1. .deb：安装到 /opt/yunyin，依赖系统的 libmpv（apt 会自动安装）。
PKG="$WORK/deb"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/yunyin" "$PKG/usr/bin" "$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/256x256/apps"
cp -a "$BUNDLE/." "$PKG/opt/yunyin/"
ln -s /opt/yunyin/yunyin "$PKG/usr/bin/yunyin"
sed 's#^Exec=.*#Exec=/opt/yunyin/yunyin %U#' "$ROOT/tool/linux/yunyin.desktop" > "$PKG/usr/share/applications/yunyin.desktop"
cp "$ROOT/linux/runner/resources/app_icon.png" "$PKG/usr/share/icons/hicolor/256x256/apps/yunyin.png"
{
  echo "Package: yunyin"
  echo "Version: $VERSION"
  echo "Architecture: $DEB_ARCH"
  echo "Maintainer: Marginal-Z <yy19273767397@gmail.com>"
  echo "Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2 | libmpv1"
  echo "Section: sound"
  echo "Priority: optional"
  echo "Homepage: https://github.com/Marginal-Z/YUNYIN"
  echo "Description: 云音 - 第三方网易云音乐客户端"
  echo " 跨平台第三方网易云音乐客户端，支持切换播放源。"
} > "$PKG/DEBIAN/control"
dpkg-deb --root-owner-group --build "$PKG" "$DIST/YunYin-$VERSION-linux-$ARCH.deb" >/dev/null

# 2. 便携包附带 libmpv：linuxdeploy 复制依赖并把 RUNPATH 设为 $ORIGIN。
#    放在独立的 lib/mpv 中，不进入主程序的库搜索路径；
#    GTK 宿主进程本来就会加载的系统库（glib、cairo、X11/Wayland、GL 等）不打包，避免新旧版本冲突。
LIBMPV="$(ls /usr/lib/"$MACHINE"-linux-gnu/libmpv.so.[0-9] | sort -V | tail -n1)"
fetch linuxdeploy "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$MACHINE.AppImage"
"$WORK/linuxdeploy" --appdir "$WORK/mpv" --library "$LIBMPV" >/dev/null
EXCLUDE='^(libglib-2|libgobject-2|libgio-2|libgmodule-2|libgthread-2|libgtk|libgdk|libatk|libatspi|libcairo|libpango|libharfbuzz|libfreetype|libfontconfig|libpixman|libpng16|libX|libxcb|libxkbcommon|libwayland|libepoxy|libGL|libEGL|libdrm|libgbm|libdbus|libsystemd|libffi|libpcre2|libselinux|libmount|libblkid|libz\.|liblzma|libzstd|libstdc\+\+|libgcc_s|libexpat|libuuid|libfribidi|libthai|libdatrie|libgraphite2|libbrotli)'
mkdir -p "$BUNDLE/lib/mpv"
for f in "$WORK"/mpv/usr/lib/*.so*; do
  name="$(basename "$f")"
  echo "$name" | grep -qE "$EXCLUDE" || cp -L "$f" "$BUNDLE/lib/mpv/$name"
done
echo "已附带 $(ls "$BUNDLE/lib/mpv" | wc -l) 个库（含 $(basename "$LIBMPV")）"

# 3. tar.gz（便携）
tar -C "$BUNDLE" -czf "$DIST/YunYin-$VERSION-linux-$ARCH.tar.gz" .

# 4. AppImage（便携）
APPDIR="$WORK/YunYin.AppDir"
mkdir -p "$APPDIR/usr/bin"
cp -a "$BUNDLE/." "$APPDIR/usr/bin/"
cp "$ROOT/linux/runner/resources/app_icon.png" "$APPDIR/yunyin.png"
cp "$ROOT/tool/linux/yunyin.desktop" "$APPDIR/yunyin.desktop"
printf '#!/bin/sh\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/usr/bin/yunyin" "$@"\n' > "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
fetch appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$MACHINE.AppImage"
ARCH="$MACHINE" "$WORK/appimagetool" --no-appstream "$APPDIR" "$DIST/YunYin-$VERSION-linux-$ARCH.AppImage"

ls -lh "$DIST"
rm -rf "$WORK"
