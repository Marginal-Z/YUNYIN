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
- 本机**没有 cmake，也没有 Android SDK**：Linux 桌面程序和 Android 都只能靠 CI 编译。adb 在 `~/platform-tools/adb`。
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

之后的提交（都已推送，`git log ae9a8e9..HEAD` 可看全部）：

| 提交 | 内容 |
| --- | --- |
| `dc859e7` `21e72c7` | 实时语音对话（SSE 流式、边生成边朗读、连续对话、打断）；语音控制云音本身 |
| `d49cfac` `9c8dfee` | 只说中文；唤醒词设置改成弹窗；音色全是男声的修复（自动下载离线声音，系统朗读按音高选男女声） |
| `766259e` | 酷狗概念版账号（appid 3116 等常量来自 MakcRe/KuGouMusicApi，MIT） |
| `5174a20` `c1ea73d` `e6eb86c` `8db6f65` | 页面转场掉帧：缩放与淡入作用在快照上（`lib/core/ui/transition_snapshot.dart`），动画延后一帧起步，动画中每 80 毫秒重拍快照 |
| `5b7382a` | 酷狗登录页、音效页的显示修复 |
| `23fcb07` | “流畅度检测”换成“问题诊断”（`lib/core/diagnostics.dart`、`lib/features/settings/diagnostics_page.dart`） |
| `a5e7e81` | 晚星的模型被上游重新上传，校验值更新；CI 增加 `tool/ci/check_model_digests.sh` |
| `3749176` | 小柚、清川换成完整精度的 Piper 模型 |
| `632ae67` | Android 16 预测性返回：启动时就声明由云音处理返回键（此前可能按返回直接退出） |

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

## 6. 进度与还没做完的事

### 6.1 已完成并在真机（三星 S23 Ultra，One UI，SM-S9180）上验证

- **安装**：覆盖安装 1.1.25，数据保留。
- **滑动帧率**：120 帧。
- **桌宠悬浮窗**：背景透明；点按开始听、气泡、拖动、回到云音时自动收起都正常。长按改为松手后再打开云音（之前会误触云音界面）。
- **实时语音对话**（`lib/assistant/llm_client.dart` 的 `stream`、`AssistantController.submit`）：
  - 回答边生成边显示、边朗读。
  - 连续对话：读完自动继续听，几秒不说话就结束。
  - 外放时说唤醒词可以打断朗读。
  - 戴耳机时直接开口也能打断（`VoiceService.headset` 判断声音是否从耳机播放）。打断检测只在真正发出声音时打开（`SpeechOutput.audible`）；之前在大模型生成时就打开，被歌声误打断。
- **语音控制云音本身**：`intents.dart` 的 `AppIntent`，以及大模型函数 `control_app`。
- **指令读音纠错**：`command_fixer.dart`。另外，连续对话中又说的唤醒词会被去掉（`WakeWords.strip`）。
- **隐私政策**：补充了云端语音引擎与桌宠的说明，`kConsentVersion` 升到 3，已安装的用户会被重新询问。
- **语音架构文档**：`docs/云音助手语音架构.md`。
- **三星图标问题已查清**：用户套用了 Good Lock 主题公园的图标主题（`current_sec_appicon_theme_package`）。它按包名替换图标，与云音的图标入口无关，所以无法也不应该绕过。外观页检测到这种情况时会给出说明。

### 6.2 还需要注意

- **音色评测**（2026-11-14，`test/zz_tts_eval_test.dart` 只在本地用，未提交）：同两句话，SenseVoice 回识准确率与合成速度（RTF，Ryzen 9 8945HX 两线程）：
  - 现有：云汐 huayan 94.6% / 0.04，小柚 xiaoya int8 100% / 0.16，晚星 baker 97.3% / 0.04，清川 chaowen int8 98.6% / 0.15，暮言 ZhiHuiLaoZhe 94.6% / 0.22（16 kHz 角色声）。
  - 完整精度 xiaoya、chaowen：都是 100% / 0.05（已换上）。
  - 候选：MeloTTS zh_en 95.9% / 0.29（44.1 kHz，单个女声，fp32 159 MB；发布包里的 int8 文件只有 133 字节，是坏的）；Matcha zh-en 98.6% / 0.03（16 kHz，要配 vocos-16khz-univ）；Kokoro v1.1 int8 多个声音 98–100%，但 RTF 0.8–1.1、加线程几乎不变，骁龙 865 上做实时对话太慢。
  - 试听页（17 个样本）：https://claude.ai/artifact/ToRPyR2apLKr8gGqHdzdZ1 ，等用户听完选定后再替换云汐、暮言等音色。
- **退出原因**：`adb shell dumpsys activity exit-info com.marginalz.yunyin` 里近期全是三星 MARs 在后台 FORCE STOP（内存 0.8–1.9 GB），没有崩溃记录。

- **默认朗读的声音**：没下载离线声音、也没配置云端引擎时，所有音色都退回系统朗读（三星上是 com.samsung.SMT），听起来是同一个声音。桌宠页和音色中心都有下载提示，可以考虑在打开语音唤醒时引导下载默认音色。
- **识别结果**：真机上偶尔整句识别得比实时字幕还差（字幕是“切换到浅色模”，最终结果却是“切换到检设模式”），目前靠读音纠错兜底。
- **日志**：logcat 里有 Impeller 的校验警告 `SetInheritedOpacity`，不影响显示，还没查是哪个控件导致的。
- **云端语音引擎**（CosyVoice、Fish Audio、ElevenLabs）：还没用真实密钥测试过。

### 6.3 测试手机

- adb 在 `~/platform-tools/adb`。Android 安装包由 CI 构建，用 `gh run download <run> --name YunYin-android` 下载后，用 `adb install -r` 覆盖安装。
- 需要说话的测试请用户来说，同时在后台每 1.5 秒截一次屏，并记录 logcat 来分析。

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
