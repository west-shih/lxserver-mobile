# LXServer Mobile

A Flutter-based mobile music player built specifically for LXServer.

基于 Flutter 开发的 LXServer 专属移动音乐客户端，目标支持 Android 和 iOS。

## 项目目标

- 完整适配 [LXServer](https://github.com/XCQ0607/lxserver) 原生 API。
- 支持多平台音乐搜索、排行榜、歌单与收藏。
- 支持音乐播放、歌词、音质切换及后台播放。
- 支持移动端本地缓存与下载。
- 与 LXServer 保持歌单和用户数据同步。
- 提供符合 Android / iOS 使用习惯的移动端体验。

**项目原则：优先实现 LXServer 的完整能力，而不是追求兼容更多音乐服务。**

本项目是独立开发的第三方客户端，非 LX Music 或 LXServer 官方项目。

## 当前状态

项目处于规划阶段，尚未创建 Flutter 工程，也未验证服务端 API。
本文中的功能是目标范围，不代表已经实现。

## 文档导航

- [产品大纲](docs/PRODUCT.md)：功能范围、页面结构、第一版边界。
- [开发路线](docs/ROADMAP.md)：里程碑与验收条件。
- [架构约定](docs/ARCHITECTURE.md)：模块划分、依赖方向、数据边界。
- [API 调研清单](docs/API.md)：证据、接口契约和待确认能力。
- [开发指南](docs/DEVELOPMENT.md)：环境、运行、检查与 Git 习惯。
- [AI 协作指南](AGENTS.md)：所有 AI 修改本仓库时遵守的约定。
- [AI 任务模板](docs/AI_WORKFLOW.md)：如何描述任务和交接进度。
- [技术决策记录](docs/DECISIONS.md)：已确认和待定的技术选择。

## 开发环境

计划使用 Flutter stable、Dart、IntelliJ IDEA 与 Flutter/Dart 插件。
先在 Android 真机验证核心流程；iOS 构建和调试需要 macOS 与 Xcode。
具体 SDK 版本在初始化工程时记录，运行步骤见开发指南。
