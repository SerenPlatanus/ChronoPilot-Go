# ChronoPilot-Go：Agent 与 MCP

2026-10-15。已恢复并启用 Agent/MCP；先前“暂停开发”的记录仅描述历史阶段。

## 首版范围（用户已确认）

Agent 只安排已有的作业、个人任务和考试复习。先在事项页建立事项，填写预计用时；模型不能猜时长，也不能从聊天直接创建新任务。已有课表、考试本身、手动固定日程都作为避让时段。考试的预计用时表示计划投入的复习时间。

安排范围为未来31天；不支持重复规则、任何通知或后台常驻服务。

## App 使用

1. 设置中填写本科账号并手动同步；暂不登录也可以使用手动事项。
2. 给需要安排的事项填写预计用时、截止日期。复习计划需要已明确的考试日期。
3. 设置中填写自己的 DeepSeek API Key。默认 `deepseek-flash`，也可填写账户支持的模型 ID。
4. Agent 新建会话，说明安排目标和限制。每次请求先检查学校同步，再将当前时间、未来事项、逾期任务、明确填写的偏好和同步状态组成 JSON 注入上下文。
5. 模型回复中的方案卡展示新增/修改/删除的原时间和新时间。点击一次“确认并写入日程”才保存；也可放弃。
6. 后续对话可以调整已保存的 Agent 时间块。只允许调整尚未开始的块；手动日程在事项页编辑。

新一轮对话会让本会话旧的待确认方案失效。已应用方案会保留 applied 状态供后续对话参考。请求可以取消；失败可以重试上一条，不重复保存用户消息。历史会话可切换、重命名、删除。删除会话不删除已经确认的日程。

API Key 只作为官方 DeepSeek HTTPS 请求的凭据；学校账号密码不进入模型上下文。模型可看到事项备注和偏好。历史保存在本地，发送时只取最近12条消息和其方案状态，避免每次携带全部历史。

## 排程的约束与数据一致性

- 工具必须带最近上下文里的 `contextVersion`。事项或偏好变化后，旧版本不能提出方案，需重新读取。
- 每个新增块必须关联未完成的 `homework/task/exam`，且用户已填写预计用时。
- 整分钟、明确时区；结束晚于开始，不能安排过去。
- 不能超过任务截止或考试开始时间；不能与课程、考试、固定日程或其他块重叠。
- 总分配时长包含过去和已完成的关联时间块，避免多次请求重复分配整个任务用时。
- 确认时重新校验数据与偏好；保存事项和会话的 applied 状态使用同一事务。重复点击不会重复写入。
- 学校数据不变的刷新不会改变事项版本；已完成的学校事项从待办源消失后保留历史。
- 完成或删除任务会清理它的未来 Agent 块。学校时间/截止或用户用时变化导致已确认块不再合法时，页面和模型上下文显示冲突，**不会擅自移动它们**。

## MCP 接入

设置 → 启动 MCP → 复制本次 Bearer 令牌。默认地址：

```text
http://127.0.0.1:8765/mcp
Authorization: Bearer <本次令牌>
```

只监听 Android 本机，退到后台会停止；再次开启会生成新令牌。无通知、前台服务或开机启动。使用外部电脑时通过 USB 转发：

```bash
adb forward tcp:8765 tcp:8765
python3 tools/mcp_smoke.py
```

脚本会隐藏输入令牌，只做初始化、发现工具与读取上下文，不提交方案。也可从环境变量 `CHRONOPILOT_MCP_TOKEN` 读取令牌。

支持 Streamable HTTP 的 JSON 响应模式，协议版本 `2025-11-25`，兼容 `2025-03-26`、`2025-06-18`。是无会话状态的 HTTP 接口，不返回 MCP-Session-Id；不提供 SSE 或旧式 SSE 端点，GET 返回405。POST 必须同时接受 `application/json` 和 `text/event-stream`。

| 方法/工具 | 作用 |
|---|---|
| initialize / ping | 初始化及连接检查 |
| tools/list | 工具定义发现 |
| get_schedule_context | 获取日程 JSON、contextVersion、同步状态及冲突提示 |
| propose_schedule | 按当前版本提交待确认草稿，创建一个 App 内 MCP 会话；返回 sessionId/draftId |
| resources/list / resources/read | 读取 `chronopilot://schedule/context` |
| resources/templates/list | 返回空模板列表 |

没有 apply、删除数据、修改凭据或执行命令的 MCP 工具。外部客户端同样必须在 App 里确认草稿。

提案参数示例（时间须替换为未来，ID/版本须从读取结果取得）：

```json
{
  "contextVersion": "来自最新上下文",
  "summary": "安排线性代数作业",
  "operations": [
    {
      "action": "add",
      "parentId": "已有作业ID",
      "title": "线性代数作业",
      "start": "2026-10-16T14:00:00+08:00",
      "end": "2026-10-16T14:30:00+08:00"
    }
  ]
}
```

修改用 `action=update` 和现有 Agent 块 `id`，只提供要改的 title/start/end；不能更换 parentId。删除只传 `action=delete` 和 id。

## 维护入口

- `planner/agent_tools.dart`：上下文、工具 schema、版本与时间校验、原子确认。
- `planner/chat_controller.dart`：模型调用循环、取消、重试、会话消息保存。
- `planner/draft_card.dart`：变更对照、确认/放弃和过期状态。
- `planner/mcp_server.dart`：HTTP/JSON-RPC、鉴权、版本协商、资源/工具分派、启动停止。
- `planner/schedule_audit.dart`：已确认块与当前事项的一致性检查。
- `services/agent/deepseek_client.dart`：固定官方 HTTPS 地址、请求超时、大小限制及错误映射；测试可替换 transport。
- `planner/repository.dart`：串行存储事务、学校数据合并、消息追加与原子草稿状态。
- `tools/mcp_smoke.py`：外部客户端只读连接检查。

暂不引入独立云后端、向量数据库或重型 Agent 框架。现有会话仍随账号快照保存；如果多年历史增长很大，可在保持数据接口不变的前提下拆分会话文件。

## 验收边界

自动化测试使用本地假服务和可控模型响应，不消耗真实 API 额度。覆盖 HTTP 请求格式/错误处理、工具链、事务失败、重复确认、取消迟到响应、会话隔离、上下文版本、MCP 鉴权/协议和界面确认。

当前没有可用的新 DeepSeek 测试 Key、真实本科账号和 Android SDK/设备，所以不能将自动化通过解释为已完成真实模型、学校系统或真机的端到端验收。请按《真机验收清单》记录真实结果。

协议与 API 依据：[MCP 2025-11-25 HTTP 规范](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)、[DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)、[DeepSeek 工具调用](https://api-docs.deepseek.com/guides/tool_calls/)。

本次自动化验证：Flutter 3.38.1 / Dart 3.10，67 项测试通过；包括实际本机 HTTP 请求、MCP JSON-RPC 与手机尺寸界面测试。
