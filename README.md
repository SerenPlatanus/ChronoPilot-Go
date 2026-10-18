# ChronoPilot-Go

面向浙江大学本科生的 Android 课表与时间规划工具，基于 Celechron 重构。

**[下载 V1.0 安装包（Android ARM64，约 21 MB）](https://github.com/SerenPlatanus/ChronoPilot-Go/releases/download/V1.0/ChronoPilot-Go_V1.0.apk)** · [查看所有版本](https://github.com/SerenPlatanus/ChronoPilot-Go/releases)

## 功能

- 同步课表、学校作业与考试，支持月历和详细课表。
- 手动添加任务、考试和固定日程，支持完成勾选、分类筛选与实时倒计时。
- 内置 DeepSeek Agent，结合课表、截止时间和个人偏好规划已有事项；支持流式回复、多会话与 Markdown / LaTeX。
- 内置本机 MCP 服务器，可按需开启。
- 四种主题、浅深色模式、壁纸导入与面板透明度，支持自定义 CSS。
- 缓存优先显示，支持自动和手动刷新，不发送通知。

## 使用

1. 安装 APK，在底栏「设置」中填写本科生账号以同步学校数据；也可直接使用本地事项。
2. 使用 Agent 时，填写自己的 DeepSeek API Key，并为待安排事项填写预计用时。
3. 在 Agent 页面提出安排需求，查看方案后确认写入，之后可继续对话调整。

## 本地开发

Flutter 3.38.1 / Dart 3.10 / JDK 17。

```bash
flutter pub get
flutter run
```

## 致谢

基于 [Celechron](https://github.com/Celechron/Celechron) 开发，遵循 [GPL-3.0](LICENSE) 许可证。
