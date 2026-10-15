# ChronoPilot-Go

基于 Celechron 重构的浙江大学本科生 Android 课表与时间安排工具。

保留课表、考试、作业、个人任务、固定日程、倒计时与时间条；移除成绩/GPA、校园卡、研究生及其他平台入口，不使用通知。

内置 DeepSeek Agent 与本机 MCP 服务器。Agent 只安排已有事项，预计用时由用户填写；所有方案先展示，确认后才写入。支持持久化多会话、明确填写的长期偏好，以及后续对话调整。

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

学生在设置中填写自己的 DeepSeek API Key，保存在本机安全存储。无需独立云后端。真实学校登录、真实模型和 APK 真机效果仍需按清单验收。

保留原项目 LICENSE。本项目源自 [Celechron](https://github.com/Celechron/Celechron)。
