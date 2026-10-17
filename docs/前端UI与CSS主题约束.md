# ChronoPilot Go：前端 UI 与 CSS 主题约束

适用版本：0.1.4，2026-10-18。可交给负责艺术风格的 Agent。

## 界面与主题的边界

项目是 Flutter Android App，没有 HTML DOM。CSS 由 `lib/ui/styles.dart` 读取，`lib/ui/controls.dart` 将有限的控件规则转换成 Flutter 样式。不要假设浏览器的 CSS 特性会自动生效。

按最新需求，主题可以改变**配色、按钮边框、圆角、填充和已有容器的边缘形态**，无需把不同艺术风格限制成换色。页面仍保持原版简洁结构：接下来、日程、事项、Agent、设置；保留大课表、倒计时、课程色标、学期筛选和对话侧栏。不要加入装饰文案、海报、横幅、斜排标题或额外艺术介绍卡。

## 已注册的主题

| 文件 | `--style-id` |
| --- | --- |
| `assets/styles/default_style.css` | `default` |
| `assets/styles/cassette_future.css` | `cassette_future` |
| `assets/styles/constructivist.css` | `constructivist` |
| `assets/styles/swiss.css` | `swiss` |
| `assets/styles/custom.css` | `custom` |

新增文件还需要注册 `PilotStyle`。替换已有主题时保留原 ID。设置中风格与明暗分别保存。

## 根变量

保留模板中完整的普通 `:root { ... }`。根颜色仅支持六位十六进制 `#RRGGBB`；根变量不支持 `var()`、颜色名、渐变、图片和表达式。数字使用无单位值。

| 变量 | 用途 |
| --- | --- |
| seed | Material 基础色板生成种子 |
| paper / surface | 页面 / 卡片背景 |
| ink / muted | 主文字 / 次文字 |
| line / accent | 细线 / 操作强调 |
| stage | 选中容器 |
| screen / signal / signal-red / signal-yellow | 反色区与状态文字 |
| danger | 错误、删除语义 |
| dark-paper…dark-danger | 上述对应深色值；dark-seed 不需要 |
| radius-card | 面板、事项卡的回退圆角，0–100；已声明的 .cp-panel / 具体类优先 |
| border-card | 可选，面板、事项卡边框宽度 0–4，默认 1；大于 1 时用 ink 描边 |
| radius-glass / space-unit | 保留 24 / 8，尚非全局布局控制器 |
| paper-grain / font-ui / font-mono / signal-green | 参考字段，不据此加载字体或调节原生纹理 |

输入框通过 `.cp-field` 控制；筛选片通过 `.cp-filter-button` 控制。容器通过 `.cp-panel` 和独立容器类控制，见下文。磁带主题保留静态纹理，已移除实时背景模糊。

## 每个按钮都有独立类

例如，发送按钮在 Dart 中绑定：

```dart
PilotControl(
  className: 'agent-send',
  kind: 'icon-button',
  child: IconButton.filled(...),
)
```

对应 CSS 类是 `.cp-agent-send`。所有现有显式操作按钮已绑定独立语义类；循环生成的同类实例共享该类，例如学期筛选。

实际合并顺序固定为：**`.cp-button` → 类型类 → 独立操作类**。这不是浏览器的选择器优先级系统。完整清单见 [按钮样式类清单](按钮样式类清单.md)。

| 类型类 | 适用对象 |
| --- | --- |
| .cp-primary-button | 保存、确认等填充按钮 |
| .cp-secondary-button | 次级描边按钮 |
| .cp-text-button | 文字操作 |
| .cp-icon-button | 图标操作 |
| .cp-add-button | 悬浮添加按钮 |
| .cp-filter-button | 学期、类别、完成状态筛选 |
| .cp-segment-button | 浅深色分段选择 |
| .cp-menu-button | 会话菜单入口 |

以下是**实际被 Android App 解析**的规则：

```css
.cp-button {
  --radius: 0;
  --border-width: 2.5;
  --border-color: ink;
}
.cp-primary-button {
  --fill: accent;
  --foreground: on-accent;
  --border-color: accent;
}
.cp-agent-send {
  --radius: 2;
  --fill: accent;
  --foreground: on-accent;
  --border-color: accent;
}
.cp-item-delete {
  --foreground: danger;
  --border-color: danger;
}
```

| 控件属性 | 支持值 |
| --- | --- |
| --radius | 0–28，无单位 |
| --border-width | 0–4，无单位，0 表示无描边 |
| --border-color | ink / line / accent / paper / surface / stage / screen / danger / on-accent / transparent |
| --fill | 同上 |
| --foreground | 同上 |

控件颜色是**语义引用**，自动随浅深色改变；`on-accent` 使用强调色的对比前景，浅色通常为白，深色为深色字。不要把浅色的白字硬套到深色的浅红按钮。

解析器只支持单独的 `.cp-小写字母-连字符 { ... }` 规则；不支持逗号、后代选择器、伪类、媒体查询内的控件规则或嵌套规则。重复声明同一个类时最后一块生效。尺寸越界、未知控件属性或颜色引用会导致主题校验失败。

按下/聚焦覆盖色、禁用透明度由组件统一生成，不通过 CSS 伪类配置。业务回调、可用状态与无障碍语义由原生按钮处理。框架自动生成的返回键、日期选择器等使用 Flutter 自身主题，不属于独立操作类清单。不要使用主题规则改变按钮尺寸、操作位置或业务含义。

浮动按钮接入形状和颜色；筛选片接入形状和描边，选中状态的颜色仍由 ChipTheme 维护；会话菜单入口继承图标按钮外观，菜单内容保持原生行为。

当前主题文件已移除旧 Web 参考规则。解析器只接受一个普通 `:root` 与 `.cp-*` 单类块；`body`、`.pilot-*`、`@media`、`:root[data-appearance]` 等会被拒绝。深色必须用 `dark-*` 根变量表达。

## App 内调试与容器类

“设置 → 编辑自定义皮肤 CSS”支持粘贴文本、修改、复制、载入默认模板、保存并应用；无须重新编译。导入代码的 style-id 必须是 custom。模板按钮只替换编辑框文本，点击保存前不会覆盖生效皮肤。校验失败时保留当前主题。

容器按 `.cp-panel` → 独立类合并，支持 `--radius`、`--border-width`、`--border-color`、`--fill`，不支持容器内任意后代选择器。

| 独立容器类 | 对应对象 |
| --- | --- |
| .cp-card | SurfacePanel 面板，含设置分组和方案卡 |
| .cp-item-card | 事项 / 日程列表卡片轮廓 |
| .cp-composer | Agent 输入容器 |
| .cp-field | 文本输入框外边框 |
| .cp-dialog | 对话框和底部面板轮廓 |
| .cp-drawer | Agent 历史侧栏 |
| .cp-glass | 磁带风格底部控制容器 |

`item-card` / `drawer` / `dialog` 目前主要接入轮廓，填充继续使用各组件的语义背景；不要宣称其中的 fill 已能覆盖每个像素。字段 foreground 与容器 foreground 也不改变内层文字。课程块、日历日期圆形选中标记仍使用专门的原生组件，以保障可读性和课程语义。

CSS 最长 65,536 个字符串单元。两套明暗颜色、尺寸边界和选择器会在保存前检查；文件不执行代码或下载资源。对比度由设计者检查，导入校验不等于无障碍认证。

## 可读性与交付要求

- 浅深两套同时检查。文字目标对比度至少 4.5:1，状态不能仅靠颜色传达。
- 课程颜色来自 `lib/ui/course_color.dart`，主题不要把不同学科统一成一种颜色。
- 保持点击区域与字体缩放适配；不缩小命中范围来获得“精致”。
- 检查 320 宽、手机竖屏、横屏与双倍文字；保留日历七列和课表横向滚动。
- 交付完整 CSS、效果说明及真实 Flutter 截图。不要把 HTML 模拟图当作原生验证结果。
- 运行 `flutter analyze --no-pub` 和 `flutter test --no-pub`。预览测试可加 `--dart-define=UI_PREVIEWS=true`，生成 `docs/ui-previews`。

已有主题是可用示例；`docs/templates/theme.template.css` 提供可复制的基础变量及控件规则。
