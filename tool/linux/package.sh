#!/usr/bin/env bash
# 打包 Linux 发行版：把 libmpv 及其依赖放进 bundle/lib，生成 tar.gz、AppImage 与 .deb。
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

fetch() { # 下载 AppImage 工具并允许在没有 FUSE 的环境中运行
  curl -fsSL -o "$WORK/$1" "$2"
  chmod +x "$WORK/$1"
}
export APPIMAGE_EXTRACT_AND_RUN=1

# 1. 随包附带 libmpv：linuxdeploy 会复制依赖、跳过系统核心库，并把 RUNPATH 设为 $ORIGIN。
LIBMPV="$(ls /usr/lib/"$MACHINE"-linux-gnu/libmpv.so.[0-9] | sort -V | tail -n1)"
fetch linuxdeploy "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$MACHINE.AppImage"
"$WORK/linuxdeploy" --appdir "$WORK/mpv" --library "$LIBMPV" >/dev/null
cp -n "$WORK"/mpv/usr/lib/*.so* "$BUNDLE/lib/"
echo "已附带 $(ls "$WORK"/mpv/usr/lib | wc -l) 个库（含 $(basename "$LIBMPV")）"

# 2. tar.gz
tar -C "$BUNDLE" -czf "$DIST/YunYin-$VERSION-linux-$ARCH.tar.gz" .

# 3. AppImage
APPDIR="$WORK/YunYin.AppDir"
mkdir -p "$APPDIR/usr/bin"
cp -a "$BUNDLE/." "$APPDIR/usr/bin/"
cp "$ROOT/linux/runner/resources/app_icon.png" "$APPDIR/yunyin.png"
cp "$ROOT/tool/linux/yunyin.desktop" "$APPDIR/yunyin.desktop"
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/yunyin" "$@"
EOF
chmod +x "$APPDIR/AppRun"
fetch appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$MACHINE.AppImage"
ARCH="$MACHINE" "$WORK/appimagetool" --no-appstream "$APPDIR" "$DIST/YunYin-$VERSION-linux-$ARCH.AppImage"

# 4. .deb（安装到 /opt/yunyin）
PKG="$WORK/deb"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/yunyin" "$PKG/usr/bin" "$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/256x256/apps"
cp -a "$BUNDLE/." "$PKG/opt/yunyin/"
ln -s /opt/yunyin/yunyin "$PKG/usr/bin/yunyin"
sed 's#^Exec=.*#Exec=/opt/yunyin/yunyin %U#' "$ROOT/tool/linux/yunyin.desktop" > "$PKG/usr/share/applications/yunyin.desktop"
cp "$ROOT/linux/runner/resources/app_icon.png" "$PKG/usr/share/icons/hicolor/256x256/apps/yunyin.png"
cat > "$PKG/DEBIAN/control" <<EOF
Package: yunyin
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: Marginal-Z <yy19273767397@gmail.com>
Depends: libgtk-3-0 | libgtk-3-0t64
Section: sound
Priority: optional
Homepage: https://github.com/Marginal-Z/YUNYIN
Description: 云音 - 第三方网易云音乐客户端
 跨平台第三方网易云音乐客户端，支持切换播放源。
EOF
dpkg-deb --root-owner-group --build "$PKG" "$DIST/YunYin-$VERSION-linux-$ARCH.deb" >/dev/null

ls -lh "$DIST"
rm -rf "$WORK"
