# 源码审核与修复记录

- 日期：2026-11-01（Asia/Bangkok）。
- 仓库：`Marginal-Z/YUNYIN`，基线提交 `bdb5ed6ba38d655660d70488dd1ed4460af355dd`，版本 `1.1.16+20`。
- 工作目录：`/home/zhangyouyi/YunYin/source`。原工作目录没有源码，因此在此目录拉取了仓库。
- 首轮审核完成时修改保留在本地工作区，没有提交、推送或发布；后续获授权的构建与发布准备记录见文末。没有修改用户已安装的应用。

## 范围与方法

对仓库进行结构、依赖、危险调用和生命周期的全局检索，逐段检查核心数据、播放、下载、账号、网盘、脚本、缓存和更新链路，同时检查相关页面、平台工程及 CI 配置。运行已有测试、补充有具体故障场景的回归测试，并实际请求三个音乐平台的公开接口。这不是对全部平台完成真机验收或对源码不存在其他缺陷的保证。

## 已修复问题

P1 表示可能覆盖文件、丢失用户队列、错误执行安装脚本或泄露凭据的问题；P2 表示功能、状态或资源管理问题。

| 编号 | 优先级 | 原问题与修复 | 主要位置 |
| --- | --- | --- | --- |
| 01 | P1 | 下载文件名仅包含歌手和歌名，不同歌曲会覆盖同一文件；新文件名增加歌曲标识摘要 | `lib/data/downloads.dart` |
| 02 | P1 | 取下载地址期间尚未登记任务，重复点击会并发下载；同一歌曲现在共用一个 Future 和最终结果 | `lib/data/downloads.dart` |
| 03 | P1 | 移动端导入仅凭文件名和大小判重，可能复用或覆盖不同内容；改为按内容摘要分目录，保留原文件名 | `lib/data/local_library.dart` |
| 04 | P1 | 删除导入副本使用简单前缀，可能把 `music-backup` 等同级目录当成应用目录；增加目录分隔边界 | `lib/data/local_library.dart` |
| 05 | P1 | 快速切换多个平台，异步停止和恢复队列会乱序，尚未恢复的空队列还会覆盖原队列；同步记录目标平台并检查请求代次，恢复期间不保存占位队列 | `lib/player/player_controller.dart` |
| 06 | P1 | QQ 登录会向返回的任意跳转地址发送收集到的 Cookie；限制为 QQ 域名及标准端口，可信 HTTP 地址升级为 HTTPS | `lib/data/sources/qq/qq_source.dart` |
| 07 | P1 | WebDAV 文件地址和跳转缺少边界校验；限制文件地址同源、拒绝不安全协议与 HTTPS 降级，跨源歌词直链不附加认证，播放直链支持多级同源跳转 | `lib/data/cloud/cloud_drives.dart` |
| 08 | P1 | 更新包只按缓存文件大小判断可用，刚下载的内容也未校验；新下载及缓存包均检查大小，并核对 API 提供的 SHA256 摘要 | `lib/core/update/updater.dart` |
| 09 | P1 | 更新脚本直接拼接单引号路径，包含引号或 shell 字符时可能报错或改变命令；分别正确转义 POSIX shell 和 PowerShell 参数，并验证版本号 | `lib/core/update/updater.dart` |
| 10 | P2 | 下载失败可能留下半成品，扩展名可包含编码斜线等非法内容；使用 `.part` 文件、完成后重命名、失败后清理和音频扩展名白名单 | `lib/data/downloads.dart` |
| 11 | P2 | 下载及本地索引并发直接覆盖 JSON，存在写入竞争；改为串行保存快照并以临时文件重命名替换 | `lib/data/downloads.dart`、`lib/data/local_library.dart` |
| 12 | P2 | 播放引擎打开、定位或播放异常可能使加载状态悬挂；捕获引擎异常、结束加载并发出提示，同时防止旧异步操作覆盖新曲目状态 | `lib/player/player_controller.dart` |
| 13 | P2 | 切到无保存队列的平台会残留旧播放顺序和时长；空队列也完整重建状态 | `lib/player/player_controller.dart` |
| 14 | P2 | 下一首、上一首和跳转后未保存当前索引，播放模式也未持久化；加载曲目时保存队列，恢复已保存的播放模式 | `lib/player/player_controller.dart` |
| 15 | P2 | 拖动进度可以超出歌曲范围，非有限比例会触发数值错误；限制进度范围并忽略无效比例 | `lib/player/player_controller.dart` |
| 16 | P2 | 播放器销毁后仍保留设置与播放源监听器、EQ 定时器和进度通知器；完整解绑，并废弃尚未结束的加载及喜欢列表请求 | `lib/player/player_controller.dart` |
| 17 | P2 | 桌面歌词控制器没有释放监听器；补充对应的 `dispose` | `lib/core/lyrics_overlay.dart` |
| 18 | P2 | 洛雪初始化失败、重复停止、停止后调用、HTTP 和定时器清理不完整；统一初始化失败清理、停止幂等、立即拒绝停止后的调用，真实取消已清除的定时器，关闭 HTTP 客户端 | `lib/data/lx/lx_runtime.dart` |
| 19 | P2 | 洛雪启动期间停用或删除仍可能注册运行环境；注册前核对最新状态，管理器销毁时释放运行环境，导入保存失败时释放脚本引擎 | `lib/data/lx/lx_sources.dart` |
| 20 | P2 | 洛雪只检查返回字符串以 `http` 开头，接受无效协议；解析并校验实际 HTTP/HTTPS 地址 | `lib/data/lx/lx_runtime.dart` |
| 21 | P2 | 切换到已有缓存时没有废弃旧请求，账号缓存清空后旧请求还可回填；增加请求及缓存代次校验，首页保存时使用请求开始时的账号身份，恢复时检查代次 | `lib/core/data_cache.dart`、`lib/core/ui/feedback.dart`、首页页面 |
| 22 | P2 | 歌单分类加载期间切换分类会一直保持旧的加载锁；选择新分类时废弃旧请求并重置加载状态 | `lib/features/discover/discover_page.dart` |
| 23 | P2 | 评论加载期间切换排序不会发起新请求，旧结果可能混入新排序；允许重置请求替换旧请求，清除旧点赞状态，提交完成后先检查页面是否仍存在 | `lib/features/comments/comments_page.dart` |
| 24 | P2 | 损坏的网易云 Cookie 或账号 JSON 会中断启动；独立处理损坏配置，应用可以继续启动 | `lib/data/sources/netease/netease_source.dart` |
| 25 | P2 | 非法 Unicode 数字实体导致歌词清理异常；保留超出 Unicode 范围或代理区的原始实体 | `lib/core/text_decode.dart` |
| 26 | P2 | 收听统计的不同歌曲共用计次状态，重复播放不会重置，非正时长也可写入；按歌曲和重新开始的会话计次，忽略无效时长，写盘失败保留待保存状态，重新绑定时解绑旧监听 | `lib/data/listen_stats.dart` |
| 27 | P2 | QQ 凭据交换失败会永久复用失败 Future；失败后允许同一二维码重试，生成新二维码时清除旧交换状态 | `lib/data/sources/qq/qq_source.dart` |
| 28 | P2 | 联网实测 QQ 搜索可能返回 2001，任一歌曲请求失败又会使综合搜索整体失败；对该错误尝试同平台 Desktop 搜索接口，并在综合搜索中保留成功的其他分类，所有结果均不可用时仍报告错误 | `lib/data/sources/qq/qq_source.dart` |
| 29 | P2 | “仅 Wi-Fi 下载”“自动清理”“推送通知”“个性化推荐”只保存开关，没有业务执行；移除无效开关，将下载网络明确显示为“使用当前网络” | 设置页面 |
| 30 | P2 | QQ/酷狗联网测试仍要求已经移除的“洛雪兜底”提示；调整为检查对应平台自身的失败说明 | `test/live_qq_test.dart`、`test/live_kugou_test.dart` |

## 首轮验证结果

- 基线：`flutter analyze` 通过，已有普通测试 68 项通过。
- 修复后：完整普通测试 101 项通过，包含 QuickJS 动态库测试；新增 33 项回归测试。
- `flutter analyze --no-pub` 与 `git diff --check` 通过。
- 网易云、酷狗、QQ 音乐现有联网冒烟测试分别通过。过程中确实复现了 QQ 的 2001 失败，修复后复测；通过只代表本次接口响应，不保证第三方服务始终可用。
- UI 状态回归覆盖缓存切换、评论排序和歌单分类；缓存组件还验证了 375 和 1000 宽度。既有横竖屏、导航、播放器样式及歌词组件测试继续通过。
- Linux 发布构建已尝试，因环境缺少 CMake 而停止；同时缺少 GTK 开发包等构建工具，未执行系统软件安装。Windows、macOS、Android 原生构建及真机音频未在本机验收。

主要新增测试：`account_restore_test.dart`、`async_view_test.dart`、`downloads_test.dart`、`player_controller_test.dart`、`qq_login_security_test.dart`、`qq_search_test.dart`、`request_switching_test.dart`。其他边界用例补充在相邻已有测试中。

## 保留的边界与后续事项

- 账号和 WebDAV 密码仍保存在应用本地偏好中，没有迁移至系统密钥链；若需要防范同一系统用户读取本地文件，应单独设计跨平台安全存储和旧数据迁移。
- 导入的洛雪脚本仍需来自可信来源；同步 JavaScript 尚未做独立执行隔离及 CPU/内存配额。本轮修复生命周期和请求地址校验，没有将其改造成不可信代码沙箱。
- 旧 Release 如果没有 `digest`，仍兼容大小校验；不能将这种情况宣称为完成了密码学内容校验。摘要来自 GitHub API 的 `digest` 字段，格式参见 [GitHub 官方 Releases API 文档](https://docs.github.com/en/rest/releases/releases)。这也不替代发布者签名。
- 没有真实用户扫码确认、会员账号、实际 NAS 和全部系统环境，因此未声称这些外部状态已经完整验证；未调整会员权限或绕过平台访问限制。
- 下载目前使用当前网络。仅 Wi-Fi 限制、应用自定义自动清理和其他被移除的占位开关，需要真实业务实现后才能重新提供。

复核可在仓库目录运行 `git diff`、`flutter analyze --no-pub` 和 `flutter test --no-pub`。QuickJS 测试需按 README 配置 `LIBQUICKJSC_TEST_PATH`；联网测试使用 `--run-skipped --tags live`，会受第三方服务状态影响。

## 用户反馈专项复核：QQ 20252 / 酷狗 30020

用户明确反馈 QQ 扫码失败 20252、酷狗所有歌曲播放失败 30020。本轮只继续处理这两项；洛雪曲库管理依用户要求暂缓，不把首轮审核称为完整验收。

### QQ 扫码

- 原流程缺少凭据交换的 `tmeLoginType: 2`，授权范围和 `openapi` 参数也不匹配 QQ 互联流程。现在固定向 QQ 互联的 `ssl.ptlogin2.graph.qq.com/check_sig` 提交扫码签名及应用参数，使用对应授权范围，并补齐 QQ 登录类型。
- 授权码按 URI 查询参数解码，合并的 `Set-Cookie`（包含 Expires 逗号）可正确解析，删除的 Cookie 不再被保留；必须取得 `p_skey`，不再拿普通 `skey` 冒充。
- 新二维码、关闭扫码页和退出账号废弃未完成的旧请求，避免旧响应覆盖新状态。凭据交换报错不接受响应中的账号或 Cookie，不覆盖已登录账号；资料请求也不能在退出后回填。
- 对照的是 [QQMusicApi 作者维护的登录实现](https://github.com/L-1124/QQMusicApi/blob/main/qqmusic_api/modules/login.py)，不是 QQ 官方稳定 API 承诺。上述参数缺陷已经修正，但没有用户实际扫码确认，不能据此断言所有账号的 20252 已消失。

### 酷狗播放

- 对酷狗公共搜索结果中的免费歌曲实测，`/play/songinfo` 和旧的 `/yy/index.php?r=play/getdata` 都返回 `status: 0, err_code: 30020`，数据含 `is_publish: 1, privilege: 0` 及 `SSA-CODE` / `SSA-HMID`。这次复现是人机验证挑战，不是“所有歌曲都需要会员”，换旧接口也不能解决。
- [酷狗官方播放器脚本](https://www.kugou.com/yy/static/js/play/playbyAudio.js) 对这类响应调用 `KgUser.antiBrush`；[官方登录脚本](https://staticssl.kugou.com/common/js/min/login/kguser.v2.min.js) 提供 `h5.kugou.com/apps/verify-h5/dist/` 验证入口。应用现在保留挑战参数，显示“打开官方验证”，由用户完成验证后重新播放；下架或受限歌曲与验证挑战分开处理。没有模拟或绕过验证码。
- 旧实现丢弃用户 Cookie 内的 `kg_mid` / `kg_dfid`，并每天变更合成设备标识。现在保留登录设备标识并持久化游客设备；完整 Cookie 导入说明要求先在官网正常播放、完成验证，且不要只复制账号字段。已有仅含账号的旧配置，需要重新导入完整 Cookie。
- 正确遍历空主地址后的备用地址，不再强制把官方 HTTP 音频地址改成 HTTPS；识别实际音质和官方试听状态。只有成功响应中的有效 HTTP(S) 地址才能被使用，登录 Cookie 不发送给音频 CDN。
- 网页登录不再重叠轮询、去掉引号破坏 Cookie、保存失败后永久停止轮询，或把凭据保存到异步期间切换后的平台；仅在酷狗 HTTPS 页面读取 Cookie。粘贴框在退场完成后释放控制器。

### 本轮验证与尚未完成的验收

- 新增 QQ 完整凭据交换、20252 失败保护、退出后旧扫码无效，酷狗设备参数、备用地址、试听、30020 官方验证路由、下架分支和无效地址，播放器验证提示以及 Cookie 登录界面等回归测试。
- 完整普通测试包含 QuickJS：111 项通过；静态分析与差异空白检查通过。酷狗专项联网测试确实进入新的官方验证分支，但没有人工完成验证码，不能把该测试通过解释成真实音频播放成功。
- QQ 真实扫码与酷狗验证后的播放仍待使用修复后的构建进行账号验收。现有已安装应用未被替换；本机 Linux 原生构建仍受缺少 CMake / GTK 开发工具限制。本轮没有发布安装包、提交或推送。

## 后续构建与发布准备

- 用户授权后，修复提交 `ac29c153fa7ba2f9b3a05dbc971cf8f41e05f04c` 已推送至专用分支 `codex/audit-login-playback-20261101`，没有合并或修改 main。
- [全平台构建 41306774858](https://github.com/Marginal-Z/YUNYIN/actions/runs/41306774858) 成功，静态检查、测试及四个平台的音频管线验证均通过。共生成 13 个开发构建安装包，本地已下载并核对完整性及架构；音频管线测试不等于真实账号登录和播放验收。
- 用户随后要求正式发布。最新正式版本为 `v1.1.15`（`1.1.15+19`），本次沿用源码中已准备好的 `v1.1.16`（`1.1.16+20`），将本轮更新说明并入该版本，通过原有标签 CI 重新构建正式安装包后发布。最终状态以对应 GitHub Actions 和 Release 记录为准。
