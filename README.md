# 云音 YunYin

第三方网易云音乐客户端，按《云音 音乐客户端设计稿》实现：浅色优先的光晕背景、弥散阴影与 Liquid Glass 导航，附完整深色模式。
一套 Flutter 代码同时产出 **Android / Windows / Linux / macOS**（并保留 iOS、Web 工程），播放源做成可插拔接口，后续可以接入其他平台。

官网与下载：<https://marginal-z.github.io/YUNYIN/>

## 功能

| 模块 | 内容 |
| --- | --- |
| 首页 | 每日推荐（登录后为个性化日推，未登录为飙升榜精选）、歌单精选、最近播放；桌面端附私人雷达 |
| 发现 | 推荐（新碟横幅 + 飙升榜）、排行榜、电台、新碟 |
| 乐库 | 我喜欢 / 最近播放 / 已下载 / 收藏的歌单，我创建的歌单，收藏的专辑、关注的歌手 |
| 本地音乐 | 导入 MP3 / FLAC / M4A / OGG / WAV 等文件（桌面端可导入整个文件夹），读取标签、封面与内嵌歌词，可与在线歌曲混合播放 |
| 歌单 / 专辑 / 电台 | 播放全部、随机播放、批量下载、加入队列 |
| 正在播放 | 背景按封面动态取色；封面、进度拖动、随机 / 单曲循环、喜欢、歌词预览 |
| 歌词 | 当前行逐字填色、弹簧曲线滚动与缩放，支持翻译、点击跳转、拖动浏览；Android 全屏沉浸显示，控件闲置后自动隐藏 |
| 播放队列 | 顺序 / 随机 / 单曲循环，拖动排序，左滑移除，清空 |
| 评论 | 推荐 / 最热 / 最新，点赞，发表评论 |
| 搜索 | 搜索历史、热搜榜；综合 / 歌曲 / 歌手 / 专辑 / 歌单，关键字高亮 |
| 歌手页 | 关注、播放热门、热门歌曲 / 专辑 / 相似歌手 |
| 登录 | 手机验证码、扫码、邮箱 / 手机密码 |
| 设置 | 音质、淡入淡出、音量均衡、睡眠定时、播放源切换、仅 Wi-Fi 下载、下载音质、清除缓存；外观二级页面：浅色 / 深色 / 跟随系统、五种主题色、应用图标跟随主题色、封面取色、歌词字号 |
| 更新 | 启动时检查 GitHub Releases，下载与当前平台、架构、安装方式匹配的安装包并覆盖安装（见下文） |
| 桌面端 | 玻璃侧边栏、前进 / 后退、红黄绿窗口按钮（关闭 / 最小化 / 最大化）、窗口毛玻璃开关、快捷键、迷你模式 |

桌面快捷键：空格 播放/暂停 · Ctrl+← / → 上一首 / 下一首 · Ctrl+↑ / ↓ 音量 · Ctrl+F 搜索 · Ctrl+M 迷你模式。

窗口宽度 ≥ 860 时使用桌面布局（侧边栏 + 底部播放条），否则使用移动布局（悬浮玻璃导航 + 迷你播放条），所以平板横屏、窄窗口都能自动切换。

## 技术架构

- **Flutter 3.47**：Android / Windows / Linux / macOS / iOS / Web 共用一套界面代码。
- **media_kit**（libmpv）：全平台音频播放；音量均衡按网易云提供的响度增益调整音量。
- **provider**：`AppSettings`、`SourceManager`、`PlayerController`、`DownloadManager`、`LocalLibrary`、`UpdateManager`、`AppNav` 等状态对象。
- **window_manager**：桌面端无边框窗口与自绘窗口按钮。
- 设计 token 集中在 `lib/core/theme/palette.dart`（浅色 / 深色两套，均取自设计稿）；
  玻璃、CSS 风格外阴影 / 内阴影、`linear-gradient` 角度、三团 `radial-gradient` 光晕在 `lib/core/ui/` 中按 CSS 语义实现，以便一比一还原。

```
lib/
├── core/            主题 token、设置、通用组件（玻璃、卡片、按钮、开关、分段控件、图标、封面）
├── data/
│   ├── models.dart  与平台无关的数据模型
│   ├── downloads.dart
│   └── sources/
│       ├── music_source.dart     播放源接口
│       ├── source_manager.dart   注册与切换
│       ├── local/                本地音乐
│       └── netease/              网易云音乐（weapi / eapi 加密，直连官方接口）
├── player/          播放队列、播放模式、淡入淡出、睡眠定时、历史
└── features/        各页面（移动端与桌面端）
```

## 接入新的播放源

1. 新建 `lib/data/sources/<平台>/<平台>_source.dart`，继承 `MusicSource`。
2. 在 `features` 中声明支持的能力（`SourceFeature`），只实现这些方法即可；未实现的入口会自动隐藏或提示不支持。
3. 在 `SourceRegistry.create()` 中加入实例。设置 → 播放源 里即可切换。

每首歌都带 `sourceId`，所以播放队列可以混合不同平台的歌曲，播放时会找回各自的源取播放地址。

## 构建

```bash
flutter pub get
flutter run                        # 当前设备
flutter build apk --release        # Android
flutter build windows --release    # Windows（需在 Windows 上构建）
flutter build linux --release      # Linux
```

Linux 构建需要：`clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev`。

推送到 `main` 后 GitHub Actions 会自动执行检查与测试并构建各平台安装包；推送 `v*` 标签会发布到 Releases。

### 发行包与架构

| 平台 | 架构 | 文件 | 说明 |
| --- | --- | --- | --- |
| Android | arm64-v8a / armeabi-v7a / x86_64 | `*-android-<abi>.apk` | 绝大多数手机选 arm64-v8a；不确定就用 universal |
| Android | 全部 | `*-android-universal.apk` | 体积较大，任何设备都能装 |
| Windows | x64 | `*-windows-x64-setup.exe` | 安装程序，安装到用户目录，无需管理员权限；推荐 |
| Windows | x64 | `*-windows-x64.zip` | 便携版，解压运行 `yunyin.exe`；Windows on ARM 可通过系统的 x64 转译运行 |
| Linux | x64 / arm64 | `*-linux-<arch>.deb` | `sudo apt install ./文件名.deb`，自动安装 libmpv |
| Linux | x64 / arm64 | `*-linux-<arch>.AppImage` | 便携版，内置 libmpv，`chmod +x` 后直接运行 |
| Linux | x64 / arm64 | `*-linux-<arch>.tar.gz` | 便携版，内置 libmpv，解压后运行 `./yunyin` |
| macOS | Intel + Apple 芯片 | `*-macos-universal.zip` | 未签名，首次打开请右键 → 打开 |

### 应用内更新

设置 → 关于与更新 可以手动检查，默认启动时也会自动检查。云音读取 GitHub Releases 的最新版本，只在版本号更高时提示，
按当前的安装方式下载对应安装包并覆盖安装，完成后自动重新打开：

| 安装方式 | 更新方式 |
| --- | --- |
| Android | 下载与当前相同 ABI 的 APK，交给系统安装器覆盖安装（首次需允许“安装未知应用”） |
| Windows 安装程序 | 静默运行新版安装程序，固定 AppId 覆盖原目录；安装程序拒绝静默降级 |
| Windows 便携版 | 退出后把新版 zip 解压覆盖到原目录 |
| deb | 通过 `pkexec apt-get install` 升级软件包 |
| AppImage | 原子替换 `$APPIMAGE` 指向的文件 |
| tar.gz 便携版 | 退出后解压覆盖原目录 |
| macOS | 退出后替换 `.app` |

Android 发布包使用固定的发布密钥签名（CI 从 `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` 两个 secrets 读取，
本地放在 `android/key.properties` 与 `android/app/yunyin-release.keystore`，均不入库，可用 `tool/android/set_signing_secrets.sh` 写入 secrets）。
没有配置密钥时本地构建退回调试签名，而标签发布会直接失败，避免发布无法覆盖安装的 APK。
1.0.x 版本使用的是临时签名，Android 用户需要卸载一次再安装 1.1.0，之后即可应用内更新。

更新说明取自 `CHANGELOG.md` 中对应版本的段落。

### 官网

`website/` 是静态官网，推送到 `main` 后由 `.github/workflows/pages.yml` 部署到 GitHub Pages；下载链接在访问时从 GitHub Releases 读取，发布新版本无需改动官网。

测试：

```bash
flutter test                                   # 单元测试（加密算法、歌词解析与动效、更新）
flutter test --run-skipped --tags live         # 联网测试网易云接口与真实播放（需要 libmpv）
flutter test integration_test -d <设备>         # 音频链路集成测试（CI 在 Android 模拟器与三大桌面系统上运行）
```

## 平台说明

- **刷新率**：Android 启动时请求屏幕支持的最高刷新率（90 / 120 / 144Hz…），iOS 开启 ProMotion，Windows 与 macOS 由 Flutter 引擎跟随显示器刷新率出帧。
  Linux 版 Flutter 引擎目前没有接入系统垂直同步，固定以 60Hz 出帧，这是引擎本身的限制。
- **Linux 流畅度**：Wayland 下默认让 GTK 用 OpenGL 绘制窗口（`GDK_GL=always`），并让 Dart UI 在独立线程运行；
  若个别驱动出现显示异常，可用 `YUNYIN_GDK_GL=0 yunyin` 启动关闭前者。
- **登录**：手机号登录优先使用验证码；网易云经常对密码登录要求安全验证，此时会提示改用验证码或扫码。
- **Web**：网易云接口不允许浏览器跨域请求，Web 版无法使用，不作为发行目标。
- **字体**：界面英文数字使用内置 Inter；中文使用系统字体（Android / Linux 为 Noto Sans CJK，Windows 为微软雅黑，macOS / iOS 为苹方）。
- **未登录**：网易云对未登录用户只提供部分歌曲的完整播放，会员歌曲为试听片段。
- **性能测试**：设置环境变量 `YUNYIN_BENCH=1` 启动桌面版，会自动滚动页面并在终端输出每帧耗时与帧间隔。

## 隐私

云音不收集任何数据。登录凭据（Cookie）只保存在本机，只发送给网易云音乐官方接口。

## 免责声明

本项目是非官方的第三方客户端，与网易公司及网易云音乐无关，仅供学习交流。音乐内容的版权归各权利人所有，请支持正版。
