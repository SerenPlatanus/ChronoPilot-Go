# 浙大日程（基于 Celechron 重构）

面向浙江大学本科生的 Android 课表与时间安排工具。

当前阶段优先交付前端与数据接口：接下来/倒计时、周日课表、分类事项、作业完成与用户预计用时、会话管理和设置。移除成绩/GPA、校园卡、研究生及其他平台入口，不使用通知。

**Agent 与 MCP 的已有代码保留，开发暂停，默认入口禁用。** 不要将当前框架当作 AI 排程已完整验收的发布版本。

- [当前框架、接口与续开发说明](docs/框架接口与续开发.md)
- [Android 精简版设计](docs/Android精简版设计.md)
- [原仓库开发介绍（历史参考）](docs/项目开发介绍.md)
- [原仓库逐文件索引（历史参考）](docs/文件功能索引.md)
- [移除的 Dart 文件清单](docs/移除文件清单.txt)

使用 Flutter 3.38.1、JDK 17 和 Android SDK：

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

API Key 由学生在设置中填写并保存在本机安全存储。保留原项目 LICENSE 与来源说明；本项目源自 [Celechron](https://github.com/Celechron/Celechron)。
