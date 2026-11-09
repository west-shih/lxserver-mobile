# 开发指南

## 环境

- IntelliJ IDEA 2026.3，安装 Flutter 与 Dart 插件。
- Flutter stable（具体版本待初始化时固定并记录）。
- Android SDK、可用 JDK、Android 真机或模拟器，以 flutter doctor 检查结果为准。
- iOS 开发需要 macOS 与 Xcode。

## 初始化前检查

```powershell
flutter --version
flutter doctor -v
flutter devices
```

尚未创建 Flutter 工程，因此目前不能运行下面的应用命令。
初始化时确认应用标识与目标平台，保留 Flutter 生成的平台忽略规则，并更新本文。

## 工程创建后的常用命令

```powershell
flutter pub get
flutter run -d <device-id>
dart format lib test
flutter analyze
flutter test
```

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
