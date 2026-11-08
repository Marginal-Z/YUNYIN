# 交接文档：云音 v1.1.25 开发中

写于 2026-11-08。仓库 `Marginal-Z/YUNYIN`，分支 `main`，pubspec 版本 `1.1.25+29`（**未发布**）。

## 1. 必须遵守的规则

- **不要发布、不要打 tag**，除非用户明确说“发布 vX”。推送 `v*` tag 会触发 CI 自动发布。
- 版本号一次只升一步（1.1.25 → 1.1.26），不跳号。
- 不绕过任何平台的权限限制或反爬 / 人机验证。之前尝试过网易云匿名注册接口的变体，被判定为绕过人机验证并拦截，**不要再试**。
- API 密钥不得写进客户端代码。云端语音、大模型都使用用户在应用里自己填写的密钥。
- 不修改测试手机的系统设置。
- 提交时只 `git add` 具体文件，**不要 `git add .`**，不要提交 `dist/`。
- 提交身份：
  ```bash
  git -c user.name=Marginal-Z -c user.email=yy19273767397@gmail.com commit -m "中文说明"
  ```
- 提交说明、代码注释和界面文字都用中文，风格与现有代码一致。

## 2. 本地验证命令

```bash
export PATH=$HOME/development/flutter/bin:$PATH
export LIBQUICKJSC_TEST_PATH=$HOME/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/linux/shared/libquickjs_c_bridge_plugin.so
flutter analyze --no-pub
flutter test --no-pub -j 4
```

- 当前结果：analyze 无问题；181 个测试通过，12 个跳过。跳过的测试需要真实模型或网络。
- 本机**没有 cmake，也没有 Android SDK 和 adb**：Linux 桌面程序和 Android 都只能靠 CI 编译，也没有连接手机。
- 需要离线语音模型的测试默认跳过。运行方法见对应测试文件开头的说明（`test/voice_engine_test.dart`、`test/voice_local_engine_test.dart`）。sherpa-onnx 的 Linux 动态库在 `~/.pub-cache/hosted/pub.dev/sherpa_onnx_linux-1.13.8/linux/x64`。

## 3. 本轮已完成的提交（都已推送）

| 提交 | 内容 |
| --- | --- |
| `9508fb9` | 评论楼层回复（网易云新版评论接口、酷狗）；“AI 助手”更名“云音助手”；三星自适应刷新率（绘制表面声明帧率，Android 15 关闭省电降帧） |
| `9d7c7e9` | 云音助手音色系统（见 4.1）；语音识别改用 SenseVoice / Paraformer 加 VAD；自定义唤醒词 |
| `d1d53a5` | 桌宠：团团、星月、阿曜，会动、有表情（见 4.2） |
| `30ccc20` | 桌宠“多久没人理”使用注入的时钟（修复：时区不同时一启动就打瞌睡） |
| `dee49b0` | CI：缓存 Gradle 与 libmpv 安卓库，构建前带重试预先下载 |
| `cbb48a0` | `tool/ci/` 下载脚本，以及这份交接文档 |
| `ae9a8e9` | 把下载脚本接进 CI 工作流，CI 全部通过 |

`CHANGELOG.md` 的 v1.1.25 一节已经写好了以上内容。

## 4. 主要代码位置

### 4.1 音色系统（`lib/voice/`）

- **`tts_types.dart`**：统一的语音合成接口 `TtsEngine`，以及 `TtsRequest` / `TtsAudio` / `Prosody` / `Emotion` / `VoiceLanguage`。
- **`voice_library.dart`**：五个预设音色（云汐、小柚、晚星、清川、暮言），每个音色在各引擎里分别指定声音 ID 或本地模型。
- **`voice_settings.dart`**：音色设置，包括密钥、代理、模型，以及用户自己覆盖的声音 ID。
- **`engines/`**：各个引擎的实现。
  - `cloud_engines.dart`：CosyVoice（DashScope WebSocket 流式）、Fish Audio、ElevenLabs。
  - `local_engine.dart`：sherpa-onnx 离线语音，模型首次使用时下载并做 SHA-256 校验。
  - `system_engine.dart`：系统朗读（Android 原生合成到文件、macOS `say`、Windows SAPI、Linux espeak-ng）。
- **`speech_output.dart`**：朗读流程。
  - 分句后边生成边播放，各句串行合成。
  - 引擎失败时自动降级到下一个引擎，失败过的引擎进入冷却期。
  - 合成结果缓存 60 MB，按最近使用淘汰。
  - 朗读时压低音乐；用户插话时 `stop()` 立即打断。
- **`prosody.dart`**：根据句子内容决定情绪、语速与停顿（只调节语速与停顿，不改变音色）。
- **界面**：`lib/features/voice/voice_center_page.dart`，即音色中心（白底蓝色强调色）。
- **未验证**：云端引擎没有用真实密钥测试过。ElevenLabs 只用模拟请求测过；CosyVoice 和 ElevenLabs 的默认声音 ID 是凭记忆填写的，用户可以在音色中心改。

### 4.2 桌宠（`lib/pet/`、`assets/pets/`）

- **`assets/pets/*.png`**：用户提供的三张角色图，抠成了透明背景。
- **`pet_rig.dart`**：每只桌宠的五官位置与颜色（`PetRig`、`PetKind`），以及状态 `PetMood`。
- **`pet_painter.dart`**：画出桌宠。
  - `PetAnimator` 根据状态和时间计算姿态：眨眼、呼吸、跳动、口型和飘出的特效。
  - `PetPainter` 在原图上画眼皮、笑眼、闭眼、各种嘴型、腮红，以及音符、爱心、Zzz、思考泡泡、汗滴和声波圈。
- **`pet_view.dart`**：会动的桌宠控件。用计时器刷新画面，应用在后台时停止刷新；头顶可以显示对话气泡。
- **`pet_host.dart`**（主程序一侧）：
  - `PetMoodRules` 根据助手、朗读和播放器的状态决定桌宠表情。
  - `PetHost` 把状态推给 Android 悬浮窗或桌面窗口，并处理点按。
- **`pet_window.dart`**：
  - `runPetOverlay()`：Android 悬浮窗里的单独 Flutter 引擎，入口是 `main.dart` 里的 `petOverlayMain`。
  - `runPetWindow()`：桌面端置顶的透明小窗口，用 desktop_multi_window 创建，与桌面歌词共用多窗口入口，靠参数 `type` 区分。
- **`android/.../PetOverlay.kt`**：Android 悬浮窗。
  - 用 `FlutterEngine(context, null, false)` 创建第二个引擎（不自动注册插件），显示在透明的 `FlutterTextureView` 里。
  - 触摸在原生代码中处理：点按开始说话（`yunyin/pet` 通道的 `tap`）；长按打开应用；拖动移动位置并记住。
- **设置页**：`lib/features/assistant/pet_page.dart`（设置 → 云音助手 → 桌宠），可以预览全部表情；打开桌宠时会把音色切换成这只桌宠的音色，并打开语音唤醒。

### 4.3 语音识别（`lib/assistant/`）

- **`voice_engine.dart`**：`VoiceRecognizer` 组合三部分：唤醒词检测 KWS、离线识别 OfflineRecognizer、端点检测 VAD。
  - 识别过程中显示实时字幕；用户说完后静音 0.7 秒结束。
  - 朗读时如果检测到用户开口，就打断朗读（`VoiceBargeIn`）。
- **`voice_models.dart`**：模型下载与校验。ASR、KWS、VAD 的 SHA-256 都写死在代码里。
- **`wake_word.dart`**：把汉字唤醒词转成拼音，转换用的读音表是 `assets/pinyin/hanzi.txt`。
- **重要约束**：后台计算用 `compute(静态函数, 数据)`，**不要用捕获了上下文的 `Isolate.run` 闭包**。它在 release AOT 模式下会失败。

## 5. CI 现状：全部通过

最后一次构建是 run 42475338239，对应提交 `ae9a8e9`，所有任务都通过：
- 静态检查与测试；
- Android（4 个 APK，`PetOverlay.kt` 已编译）、Windows、macOS、Linux x64 / arm64 的构建与打包；
- Android 模拟器、Windows、macOS、Linux 的音频验证。

### 5.1 GitHub 发布文件下载不稳定的处理

- **起因**：2026-11-08 那天，GitHub 的 `github.com/<owner>/<repo>/releases/download/...` 入口间歇性返回 504，有时 API 和网站也会超时。Android 构建要从 GitHub 下载 Gradle、libmpv，甚至 Kotlin 编译器；Windows 的 media_kit 和 Linux 打包工具也一样，当时这些任务都失败了。
- **处理**：`tool/ci/` 里的三个脚本已经接进 `.github/workflows/build.yml`。

| 脚本 | 作用 |
| --- | --- |
| `gh_release_download.sh <下载地址> <保存路径>` | 每一轮先试官方下载地址，失败就改用 GitHub API（`/repos/{o}/{r}/releases/assets/{id}`，请求头 `Accept: application/octet-stream`），最多 10 轮，每轮间隔 20 秒。使用工作流的 `GITHUB_TOKEN`。 |
| `prefetch_android.sh` | 在 android 和 audio-android 两个任务里运行。Gradle 用官网公布的 SHA-256 校验，然后让 Gradle 包装器使用本地文件（只在 CI 里改 `distributionUrl`）；libmpv 的 jar 用插件自带的 MD5 校验。 |
| `prefetch_windows.sh` | 在 windows 任务和 audio-desktop 的 Windows 任务里运行（Git Bash）。libmpv 压缩包下载到 `build/windows/x64/`，用 MD5 校验。 |

- **其他改动**：`tool/linux/package.sh` 的 `fetch()` 也改用 `gh_release_download.sh`。另外，`setup-java` 设置了 `cache: gradle`，libmpv 安卓库也用 `actions/cache` 缓存。
- **实际效果**：在 run 42475338239 里，Linux x64 打包时官方地址失败一次，改用 API 后下载成功。
- **注意**：不要改用 ghfast.top 这类第三方镜像。它们只是转发到 GitHub，GitHub 出故障时同样失败，而且有被篡改的风险。

## 6. 还没做完的事

### 6.1 桌宠：Android 真机验证（最重要）

需要在三星 S23 Ultra 上逐项确认：
- 退到桌面后悬浮窗出现，桌宠以外的区域是透明的。
- 点按开始 / 停止说话，长按打开云音，拖动后位置会被记住。
- 有气泡时窗口向上加高，桌宠本身不动。
- 回到云音时悬浮窗自动收起。

主要风险：第二个 Flutter 引擎在 Impeller 下渲染透明 `FlutterTextureView`。如果背景不透明，可以试 `FlutterSurfaceView(context, true)`，或者给第二个引擎关闭 Impeller。

另外需要关注两点：
- 桌宠引擎也会加载 `main.dart` 这个库，确认它不会触发主程序的初始化。
- 应用被系统回收后，`PetOverlay.mainChannel` 可能失效。主程序使用 audio_service 缓存的引擎，理论上活动重建后通道会重新设置。

### 6.2 实时语音对话（用户要求像 ChatGPT Voice 那样）

- `LlmClient` 改用 SSE 流式输出，包括工具调用的增量。
- 一边生成一边用 `SpeechOutput.begin()` 返回的 `SpeechTurn` 逐句朗读。
- 连续对话：回答完自动继续听，不用每次都说唤醒词。
- 朗读期间调用 `VoiceWorker.setMonitor(true)`，检测用户插话。
- 系统提示词里让大模型在句首加情绪标记，例如 `[开心]`；`ProsodyPlanner.stripTag` 已经支持解析。

### 6.3 设备控制工具（Android）

手电筒、亮度（需要引导用户授予 WRITE_SETTINGS）、按名称打开应用、闹钟与计时器（AlarmClock intent）、Wi-Fi / 蓝牙设置面板。桌面端能做的部分也一并实现。

### 6.4 其他

- 指令词的拼音模糊纠错，例如识别成“烧一首”时纠正为“上一首”。
- **三星**：
  - 加一个流畅度检测浮层，使用 `yunyin/system` 通道的 `displayInfo` 与 FrameTiming 统计。
  - 用户反馈“应用图标跟随主题色在三星上仍不生效”，**症状不明**，需要先问清楚。
- 写一份架构文档 `docs/云音助手语音架构.md`：架构、接口、核心代码与测试方案（用户最初的需求里要求过）。
- 隐私政策补充云端语音引擎的说明（填写密钥后，朗读的文字会发送到对应服务商）。

## 7. 参考：接口与已知结论

- **网易云评论**：
  - 评论列表用 weapi `/v2/resource/comments`，按热度排序时第 2 页起返回 400，改用 `/v1/resource/hotcomments`。
  - 楼层回复用 `/resource/comment/floor/get`。
- **酷狗回复**：`/mcomment/v1/hot_replylist`，必须带上评论所属的 `special_id`、`tid`、`childrenid`（即 `special_child_id`）和 `extdata`。
- **QQ 音乐**：网页接口不提供评论回复（ReplyCnt 恒为 0）。
- **mpv 音量**：三次方曲线，线性振幅系数要先开三次方根，见 `mpvVolume`。
- **语音识别评测**（合成语音指令，字错率）：

  | 模型 | 字错率 |
  | --- | --- |
  | 旧的流式 CTC | 44% |
  | Paraformer-small | 25% |
  | SenseVoice | 21% |
