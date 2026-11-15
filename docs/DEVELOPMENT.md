# 开发指南

## 环境

- IntelliJ IDEA 2026.3，安装 Flutter 与 Dart 插件。
- 当前基线：Flutter 3.47.9 stable / Dart 3.13.7；依赖版本记录于 pubspec.lock。
- Android SDK、可用 JDK、Android 真机或模拟器，以 flutter doctor 检查结果为准。
- iOS 开发需要 macOS 与 Xcode。

## 初始化前检查

```powershell
flutter --version
flutter doctor -v
flutter devices
```

已创建 Android/iOS 工程，开发占位应用标识为 dev.lxserver.mobile.lxserver_mobile，发布前需确认归属。
当前 Android SDK 37、API 37 模拟器已通过 doctor 识别；实际 compileSdk/NDK 由 Flutter 模板定义，
首次构建可能自动下载模板需要的额外 SDK/NDK，安装 SDK 37 不代表其他构建组件已经齐全。
本工程当前模板值：compileSdk/targetSdk 36、minSdk 24、NDK 28.2.13676358。
新版 Android CLI 使用 `platforms/android-36`、`ndk/28.2.13676358` 形式的包路径；
若 Flutter 自动安装传入分号格式导致找不到包，可在 SDK Manager 安装对应版本。

## 工程创建后的常用命令

```powershell
flutter pub get
flutter run -d <device-id>
dart format lib test
flutter analyze
flutter test
```

## 登录和联调

- 登录页填写 LXServer 基础地址（支持反向代理路径前缀），不填网页的 /music 或 /admin 页面路径。
- 输入后台预先创建的普通用户账号；服务端需为该用户配置可用音乐解析源。
- 模拟器访问本机服务器可使用 http://10.0.2.2:<端口>，不要使用指向模拟器自身的 localhost。
- Android 当前允许 HTTP，以兼容自建局域网服务器和 HTTP 音频；公网部署应使用 HTTPS。
- Android 已关闭应用备份，避免把安全存储会话带到其他安装环境。
- iOS 仅生成工程，尚未构建/签名/真机验证；默认 ATS 限制仍保留，HTTP 自建服务尚未适配。
- 当前只验证前台播放代码，后台保活、通知栏、锁屏和音频打断仍是后续工作。
- 不要为了试用将真实服务器凭据提交到代码或测试；自动化测试使用虚构数据。

## 模拟器自动化（测试数据）

本地测试夹具不是 LXServer 实例，不代表通过真实服务兼容性验证。它仅验证客户端的
登录 HTTP 请求、安全存储、五源切换与 Android 音频解码/暂停/进度操作。
需本机安装 Node.js 并启动 Android 模拟器。在两个终端分别运行：

```powershell
node integration_test/fixture_server.mjs
```

```powershell
flutter test integration_test/android_flow_test.dart --dart-define=LX_INTEGRATION=true --no-uninstall -d emulator-5554
```

夹具只绑定本机 127.0.0.1:18765，返回明确标注的测试歌曲和静音 WAV。
完成后停止夹具进程。LX_INTEGRATION=true 同时启用 Android 的 .integration 包名后缀与测试安全检查，
把测试会话与正常客户端分开；不要省略 --no-uninstall，Flutter 测试清理可能使用构建前 APK 的旧包信息。
测试会退出测试账号并清理测试地址，不要在真实服务创建这些测试凭据。截图仅含夹具数据，保存在测试包 code_cache。

## 当前功能验证边界

- 登录后读取可用平台，状态未知时不会误隐藏。未配置可用平台的情况由网页端管理员处理。
- “我的”可查看并播放在线收藏歌曲，刷新拉取最新个人歌单；自建歌单可确认删除、关联在线歌单可刷新同步/应用内打开来源详情。写入使用全量快照，操作前重读，避免多设备同时编辑；支持私人歌曲批量收藏、删除和排序；外部原歌单只读，真实写入仍待验收。
- 在线歌单分类/排序按各平台返回值展示，不保证所有平台提供同样分类。
- 歌词已支持基础 LRC、翻译、高亮及点击跳转；逐字、罗马音、offset 元信息待后续适配。
- 播放页左右滑动切换封面/歌词，歌曲信息右侧按钮选择音质。客户端默认无损，用户选择立即保存到本机。
- 新搜索结果按具体音质列表选择不超过偏好的最高档，跳过未标注项；历史歌单信息不完整时不把 128k 当上限。优先近期成功记录，失败后同平台降级，首选不变；全部失败尝试保留或恢复原流。
- 手机以 flutter run 连接时，终端小写 r 热重载界面，大写 R 热重启以重建控制器状态。本轮播放逻辑变更建议大写 R 后重新点歌。原生代码、插件或 Gradle 变更需停止再运行。
- 服务器未给出 type 时显示“音质未确认”，不能把请求无损等同于文件实际无损。
- 夹具用静音 WAV 验证切换流程与音质元数据；没有验证真实 FLAC/Hi-Res 音源或硬件输出能力。
- 成功档位安全保存最多 200 首 LRU，不按时间失效；同一首选下重播沿用。失败只在内存退避 30 秒，重启清除。URL 仅内存 5 分钟，失效先重新获取原档。手动重试清除当前记录；修改全局首选清除旧记录，自动降级不修改首选。退出账号清空播放记录，保留音质偏好。源配置变化在刷新时检测，未暴露的脚本内部变化由加载失败恢复或手动重试处理。
- 已读取服务端现有缓存，不自动触发服务端下载或缓存升级。旧服务端没有缓存接口时继续在线解析；仅同源缓存文件可使用带鉴权的文件 URL，不向外部音频 CDN 附加 Token。
- 尚无持久音频文件缓存或离线下载；just_audio 的临时缓冲不代表上述能力已实现。
- 列表“已缓存/已下载”来自当前账号的 /api/music/cache/list，指 LXServer 管理的存储；状态 60 秒复用，刷新音乐库可强制刷新。长按标签可看服务器上已有音质。接口失败或权限不足时不显示文件徽标，不代表明确无文件。

仅在对应目录存在时执行格式化。集成测试和真机场景随功能增加。

## Git 约定

- 小步提交，一个提交对应一个可说明的变化。
- 分支可使用 codex/<task-name>，或按团队后续约定命名。
- 应用的 pubspec.lock 纳入版本控制。
- 不提交 SDK、构建产物、IDE 私有配置、签名文件和真实凭据。
- 新增配置提供脱敏示例，写清必填项。
- 提交前查看 git diff 和 git status，确认没有无关变更。

## 排错记录

问题需包含：运行平台、SDK/服务端版本、复现步骤、预期与实际结果、脱敏日志。
播放问题额外记录前后台状态、网络状态、音频打断和系统媒体控制行为。

## 手机缓存与下载（当前实现）

文件位置、容量与离线边界见 [LOCAL_MEDIA.md](LOCAL_MEDIA.md)。运行 `flutter test test/local_media_test.dart` 验证文件生命周期；Android 测试仍使用 `--dart-define=LX_INTEGRATION=true --no-uninstall` 隔离包名及临时文件。真实音源的 FLAC/MP3/M4A 等编码、进程被杀和 iOS 需另行设备验证。不要清除正常包数据来运行夹具。

播放恢复状态位于应用支持目录 lx_playback.json，测试通过 mediaDirectory 注入临时目录隔离。进程强杀可能丢失最近 3 秒左右未补存的进度；不宣称所有系统终止场景都能收到生命周期回调。
