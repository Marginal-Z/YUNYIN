# 云音交接给 Claude

交接日期：2026-11-01（Asia/Bangkok）。本项目由 Claude 原开发，Codex 本次仅临时接手排查、修复与构建发布。用户现要求停止继续审核，先提交已修复内容，再交回 Claude。

## 1. 先看当前状态

- 实际仓库目录：`/home/zhangyouyi/YunYin/source`，不是其父目录。
- 分支：`codex/audit-login-playback-20261101`。没有合并或修改 `main`。
- 最新修复提交：`8a473834182e491fface8047630b29308bd7c0e5`，标题 `fix: harden settings and repair playback, downloads and search`。
- 本次修复与交接文档仅本地提交，尚未推送、触发构建或发布；版本仍为 `1.1.16+20`，没有修改依赖。
- 已发布的 `v1.1.16` 不含本次 `8a47383` 修复。不要把源码已修改等同于用户已安装应用已更新。
- 工作区仍有两个未提交的洛雪测试文件，以及未跟踪的 `dist/` 构建产物，详见第 4、7 节。这是刻意隔离的未完成工作，不要直接 `git add .`。
- 全面审核没有完成，不能向用户保证项目已经没有其他问题。

## 2. 已完成的修复及历史

### 本次本地提交 `8a47383`

| 范围 | 实际改动 | 回归测试 |
| --- | --- | --- |
| 设置恢复 | 偏好值安全读取；非法枚举回退；非有限音量、歌词及 EQ 参数回退/限幅；单个平台样式损坏不阻断其他样式；相关 setter 拒绝无效值 | `test/settings_restore_test.dart`，新增 4 项 |
| 下载 | `StreamInfo.trial` 为真时拒绝把试听片段保存为完整歌曲，保留失败清理逻辑 | `test/downloads_test.dart`，新增 1 项 |
| 播放异步状态 | 记录播放/暂停意图，避免取地址期间暂停后又自动播放；旧歌曲失败处理在等待停止后再次检查代次，避免过期提示干扰新歌曲 | `test/player_controller_test.dart`，新增 2 项 |
| 综合搜索 | 结果判空考虑全部分类；缺少最佳歌曲时仍显示成功的专辑/歌手/歌单；补齐移动端专辑/歌单及桌面歌手展示；分类“更多”跳转到对应标签 | `test/search_results_test.dart`，新增 6 项，覆盖 390/1200 宽度 |

本次提交共 5 个源码文件、4 个测试文件，新增 13 项回归。源码位置为 `lib/core/settings.dart`、`lib/data/downloads.dart`、`lib/data/models.dart`、`lib/player/player_controller.dart`、`lib/features/search/search_result_page.dart`。设置和搜索的部分差异是格式化/重新缩进，不是设计系统重做。

### 之前已推送并发布的工作

- 基线：`bdb5ed6ba38d655660d70488dd1ed4460af355dd`。
- 第一轮审核及 QQ/酷狗专项修复：`ac29c153fa7ba2f9b3a05dbc971cf8f41e05f04c`。
- 发布说明整理：`1fe5c1796c254213d7e321e90b6a88c583fc9375`；`v1.1.16` 标签指向此提交。
- 已发布：[v1.1.16](https://github.com/Marginal-Z/YUNYIN/releases/tag/v1.1.16)，[正式发布 CI 41308028690](https://github.com/Marginal-Z/YUNYIN/actions/runs/41308028690) 已成功，包含原有矩阵的 13 个安装包。
- 前几轮详细修复见 `AUDIT_REPORT.md` 和 `CHANGELOG.md`。审核报告按阶段记录，其中早期“未提交/未发布”的文字是当时状态；后续已经发布，不能单独引用早期段落作为当前状态。本交接文档补充最终发布结果及本次本地改动，没有重写旧报告。

## 3. 用户原始故障与验收边界

用户反馈：QQ 扫码登录失败 `20252`；酷狗所有歌曲播放失败 `30020`；另提到洛雪曲库管理，但具体需求当时表示“稍后再说”。不要擅自把洛雪管理扩展成大规模功能重构。

- QQ：此前修正了授权参数、`tmeLoginType: 2`、Cookie 和授权码处理，以及旧扫码响应覆盖状态的问题，有模拟响应回归测试；没有真实账号扫码完成验收，不能保证所有账号的 `20252` 已消失。
- 酷狗：此前实际请求复现 `30020` 且带 `SSA-CODE` / `SSA-HMID`，属于官方人机验证挑战。保留登录设备 Cookie、持久化游客标识、修复备用地址/试听识别，并提供“打开官方验证”；没有绕过验证码，也没有人工完成验证后的真实播放验收。
- 本次 `8a47383` 没有再修改 QQ、酷狗账号或接口代码。
- 用户已安装的 `/opt/yunyin` 未被替换。CI 音频管线测试用 null 输出，不等于真实扬声器播放和账号验收。

## 4. 未完成：四项洛雪回归复现

本次没有修改 `lib/data/lx/lx_runtime.dart` 或 `lib/data/lx/lx_sources.dart`，只在下述两个文件中新增了 4 项故障复现测试，故意不纳入已修复提交：

- `test/lx_runtime_test.dart`：新增 2 项。
- `test/lx_sources_test.dart`：新增 2 项。

这些改动仍在本机工作区，清洁克隆或仅获取本地提交不会带上它们。跨机器交接时可在原工作区单独导出：

```sh
git diff -- test/lx_runtime_test.dart test/lx_sources_test.dart > /tmp/yunyin-lx-repro.patch
```

| 测试名 | 复现与实际结果 | 后续处理方向（尚未实现） |
| --- | --- | --- |
| 音源明确报告初始化失败时不能作为可用运行环境返回 | 脚本发送 `lx.send('inited', {status:false, errorMessage:'初始化被拒绝', sources:{kw:{qualitys:['128k']}}})`，`LxRuntime.start` 仍成功返回 | 处理显式失败状态，传播脚本原因，并保留未提供 status 的旧脚本兼容性及初始化清理 |
| 取消 lx.request 会取消底层网络请求，而不仅丢弃回调 | 本机 HTTP 服务计数；脚本调用 `lx.request` 后立即调用返回的 cancel，服务仍收到 1 个请求；目前取消函数只删除 JS callback | 按请求 ID 真正取消底层 HTTP，清理取消映射；覆盖完成后/重复取消与 dispose，核对取消契约 |
| 损坏的音源记录不丢弃后续有效音源，并拒绝不安全的脚本路径标识 | `lx.scripts` 存入下方 JSON，调用两次 init，期望只保留 valid；当前在数字记录处抛错，后续有效项未恢复 | 按项校验、拒绝不安全 ID、使重复 init 不追加重复记录；当前综合用例先暴露损坏项问题，路径和幂等分支还应拆成独立测试 |
| 移除音源时清除遗留播放失败状态 | 给 `lastFailures['test']` 写入旧错误，移除 test 后该映射仍存在 | 删除时同时清理运行期失败状态及其他对应状态 |

恢复测试输入：

```json
[42,{"id":"../outside","name":"invalid"},{"id":"valid","name":"有效音源","enabled":false}]
```

ID 直接参与脚本文件路径拼接，相关边界应认真验证；没有完成任意路径删除利用验证，不应把代码风险描述为已验证利用。

## 5. 验证结果及复跑

交接前实际执行：

1. 普通测试全量运行（包含以上未提交用例）：**124 通过、4 失败、7 跳过**；4 个失败恰为第 4 节列出的新洛雪复现。跳过的是默认不开启的联网测试。
2. 排除这 4 个未提交用例后复跑：**124 通过、7 跳过**。
3. 静态分析最初发现搜索页面两处多余非空判断，移除后 `flutter analyze --no-pub` 通过。
4. 本次提交的 9 个 Dart 文件格式检查通过；`git diff --check` 通过。
5. 没有为本次提交重做跨平台构建、联网冒烟或真机账号/音频验收。之前正式发布 CI 的成功仅对应 `1fe5c17`，不是本次新提交。

本机工具：Flutter `3.47.7` / Dart `3.13.5`；Flutter 在 `/home/zhangyouyi/development/flutter/bin/flutter`，可先把该目录加入 PATH。QuickJS 测试需要指定动态库，不设时部分测试会跳过：

```sh
cd /home/zhangyouyi/YunYin/source
export PATH=/home/zhangyouyi/development/flutter/bin:$PATH
export LIBQUICKJSC_TEST_PATH=/home/zhangyouyi/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/linux/shared/libquickjs_c_bridge_plugin.so
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

其他机器需把 QuickJS 路径改为对应 `PUB_CACHE` 的位置；上述是 Linux x64 库。当前工作区全量命令预期会出现已知 4 个失败，不要把它当成全绿。仅验证已提交修复时，本次使用的明确排除命令为：

```sh
flutter test --no-pub --reporter expanded --name '^(?!.*(?:音源明确报告初始化失败|取消 lx[.]request|损坏的音源记录|移除音源时清除遗留播放失败状态)).*$'
```

在不含未提交用例的干净提交上，不需要这个过滤条件。联网测试需另行使用 `--run-skipped --tags live`，受服务端及账号状态影响，本次未运行。

本机日志（临时文件，不在 Git 中）：`/tmp/yunyin-handoff-tests.log` 为全量含失败结果，`/tmp/yunyin-handoff-committable-tests.log` 为排除 4 项后的通过结果。`/tmp/yunyin-handoff-analyze.log` 是整理前的两条告警记录，不是最终通过结果；最终通过结果已在终端核对。

## 6. 仅检查过的线索，不是已修复/已复现结论

以下均没有本次源码改动，也没有新增针对性回归，接手后请独立验证：

- 网易云账号代次：`lib/data/sources/netease/netease_source.dart` 中旧登录/资料刷新可能在退出后回填；旧响应 `_parse` 的 301 可能清掉较新账号。建议先用可控延迟响应验证，再设计账号代次保护；不要直接套用 QQ 参数。
- 洛雪设置页：`lib/features/settings/lx_page.dart` 的导入等待后 `_url.clear()` 缺少退场保护；文件选择/读流异常不在 `_run` 的捕获范围；URL 仅用 `startsWith('http')` 检查。
- 歌手关注：`lib/features/artist/artist_page.dart` 等待关注接口后先 setState，再检查 mounted。
- 索引恢复：下载与本地曲库的损坏记录是否会中断后续恢复，需补独立用例。
- 启动隔离：某个平台初始化异常是否会阻断其他平台，尚未补测试。
- Android 备份与凭据：当前 Manifest 没有显式备份策略，凭据仍在本地偏好/文件；需结合系统版本、云备份和设备迁移验证，不是已经证明发生了泄露。没有改 Manifest，也没有迁移到系统密钥链。
- 洛雪脚本仍须可信；没有独立执行隔离、CPU/内存配额，不是可安全运行恶意脚本的沙箱。
- Linux arm64 的 QuickJS 是已知能力限制：现有 `flutter_js` Linux 库仅 x86_64，`linux/CMakeLists.txt` 已明确 arm64 不复制该库；现有 arm64 包也未包含。不要因普通打包成功就承诺 arm64 洛雪脚本可运行。
- 执行过依赖过期/解析检查，看到 33 项有约束外新版本；未升级任何依赖，`pubspec.yaml`、`pubspec.lock` 未变。这不是完整漏洞扫描结论。

## 7. 构建、产物和交接注意事项

保持用户要求的原有平台矩阵，不擅自增加 iOS/Web：

| 平台 | 格式/架构 | 数量 |
| --- | --- | --- |
| Android | arm64-v8a、armeabi-v7a、x86_64、通用 APK | 4 |
| Windows | x64 Setup EXE、ZIP | 2 |
| Linux | x64 / arm64，各 DEB、AppImage、tar.gz | 6 |
| macOS | Intel x86_64 + Apple arm64 通用 ZIP | 1 |

- 原有 CI：`.github/workflows/build.yml`。`workflow_dispatch` 可以构建专用分支，`v*` 标签会进入发布流程；不要为“交接”重打已发布标签。
- 上轮开发构建：[41306774858](https://github.com/Marginal-Z/YUNYIN/actions/runs/41306774858)。下载的 13 个开发包在 `dist/ci-41306774858/`，含 `BUILD_REPORT.md`、`SHA256SUMS`；这是旧 `ac29c15` 的 `1.1.16-dev` 产物，不是正式包，也不含本次修复。不要把整个 dist 加进源码提交。
- 本机缺少 CMake/GTK 等 Linux 原生构建工具，未安装系统软件；此前全平台构建使用 GitHub Actions。
- 本轮没有修改 Git 全局身份；提交使用单次 `Codex <codex@openai.com>` 身份。没有把账号 Cookie、验证码或 GitHub Token 写入交接文档。
- 接手先检查 `git status`、`git log -4 --oneline` 和两份洛雪测试 diff。用户要求的是交回维护，不是继续宣称“全面修复完成”；继续修复、推送、合并或发布按用户后续安排执行。
