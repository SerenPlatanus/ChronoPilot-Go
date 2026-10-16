# ChronoPilot-Go

基于 Celechron 重构的浙江大学本科生 Android 课表与时间安排工具。

保留课表、考试、作业、个人任务、固定日程、倒计时与时间条；移除成绩/GPA、校园卡、研究生及其他平台入口，不使用通知。

内置 DeepSeek Agent 与本机 MCP 服务器。Agent 只安排已有事项，预计用时由用户填写；所有方案先展示，确认后才写入。支持流式回复、持久化多会话、明确填写的长期偏好，以及后续对话调整。

- [界面、学期筛选与主题开发说明](docs/界面与主题开发说明.md)
- [Agent/MCP 使用、约束和接口](docs/Agent与MCP使用及验收.md)
- [真机验收清单](docs/真机验收清单.md)
- [框架与数据接口说明](docs/框架接口与续开发.md)
- [Android 设计](docs/Android精简版设计.md)
- [原仓库开发介绍](docs/项目开发介绍.md) / [历史文件索引](docs/文件功能索引.md)

Flutter 3.38.1 / Dart 3.10 / JDK17 / Android SDK：

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

日常手机安装应使用按 CPU 架构拆分的 Release 包；Debug 通用包包含调试运行时和多套原生库，体积显著更大。ARM64 手机的构建命令：

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

输出为 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。当前 Release 使用本地调试签名供测试安装，公开分发前需配置自己的发布签名。

学生在设置中填写自己的 DeepSeek API Key，保存在本机安全存储。无需独立云后端。真实学校登录、真实模型和 APK 真机效果仍需按清单验收。

保留原项目 LICENSE。本项目源自 [Celechron](https://github.com/Celechron/Celechron)。

Android 独立应用标识为 `app.chronopilot.go`，与原版 `xyz.nosig.celechron` 分离，可并存安装。旧测试包沿用原版标识，属于另一应用的数据目录；安装新标识版本不会自动迁移旧包的账号、本地事项或对话。
