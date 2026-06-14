# 🦀 Crabby AI

> Your personal AI assistant, the crab way. Pure PowerShell, Windows native.

Crabby AI 是一个纯 PowerShell 实现的自托管 AI 助手，灵感来自 [OpenClaw](https://github.com/openclaw/openclaw)。无需 WSL、Node.js 或 Python——只要 PowerShell 和一个 LLM API Key。

## ✨ 特性

- 🧠 **多模型支持** — 硅基流动、智谱、DeepSeek、OpenAI 或任何 OpenAI 兼容 API
- 💾 **持久记忆** — 基于 Markdown 的记忆系统（MEMORY.md、USER.md）
- 🎭 **可定制人格** — 在 SOUL.md 中定义助手的灵魂
- 🔧 **内置工具** — Shell 执行、文件读写、网页搜索与抓取
- 🧩 **技能系统** — 用 PowerShell 脚本扩展功能
- 🖥️ **原生 GUI** — WPF 桌面界面，零依赖，美观暗色主题
- 🌐 **Web UI** — 浏览器聊天界面，跨设备访问
- ⏰ **心跳调度** — 集成 Windows 任务计划程序，7×24 自动化
- 🔒 **隐私优先** — 一切本地运行，数据不出你的机器

## 🚀 快速开始

### 前置要求

- Windows 10/11
- PowerShell 5.1+（系统自带）
- 一个 LLM API Key（推荐硅基流动，免费额度 2000 万 tokens）

### 安装步骤

#### 方式一：Git Clone

```powershell
git clone https://github.com/chenruiqi449/crabby-ai.git
cd crabby-ai
.\install.ps1
```

#### 方式二：下载安装脚本

1. 下载 [install-crabby.ps1](https://github.com/chenruiqi449/crabby-ai/raw/main/install-crabby.ps1)
2. 放到你想要的目录（如 `D:\Desktop`）
3. 右键 → 使用 PowerShell 运行，或在 PowerShell 中执行：

```powershell
.\install-crabby.ps1
```

它会自动在当前目录创建 `crabby-ai` 文件夹并生成所有文件。

### 解除脚本执行限制

Windows 默认禁止运行 PowerShell 脚本，首次使用需要执行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

输入 `Y` 确认即可。如果你不想修改全局策略，也可以每次运行时绕过：

```powershell
powershell -ExecutionPolicy Bypass -File .\crabby.ps1
```

### 配置 API Key

运行 `.\install.ps1` 会启动交互式配置向导，引导你选择 LLM 供应商并填入 API Key。

也可以手动编辑 `config\settings.json`：

```json
{
    "llm": {
        "provider": "siliconflow",
        "api_key": "你的API Key",
        "model": "Qwen/Qwen3-8B",
        "base_url": "https://api.siliconflow.cn/v1",
        "max_tokens": 1024,
        "temperature": 0.7,
        "repetition_penalty": 1.1
    },
    "user": {
        "name": "你的名字"
    }
}
```

### 开始聊天

#### 终端模式

```powershell
.\crabby.ps1
```

#### 原生桌面界面（推荐）

```powershell
.\crabby-gui.ps1
```

WPF 暗色主题，无需浏览器，零额外依赖。聊天后台执行，界面不卡顿。

#### Web UI 模式

```powershell
.\crabby-web.ps1
```

自动在浏览器打开 `http://localhost:8420`，可用手机等其他设备访问。

自定义端口：`.\crabby-web.ps1 -Port 8080`

## 📖 详细使用方法

### 交互聊天模式

启动后进入交互式聊天：

```powershell
.\crabby.ps1
```

```
  🦀 Crabby AI v1.0
  ─────────────────────────────
  Model: Qwen/Qwen3-8B
  Provider: siliconflow
  Type 'exit' to quit, 'clear' to reset context

You> 你好
🦀 你好！我是 Crabby，你的 AI 助手 🦀 有什么可以帮你的？

You> 帮我看看C盘还有多少空间
  ⚙️ Calling tool: shell
🦀 你的C盘还有 156.3 GB 可用空间，总共 512 GB，使用了约 70%。

You> exit
🦀 See you later!
```

### 单次提问模式

不需要进入交互模式，直接获取回答：

```powershell
.\crabby.ps1 -Message "今天上海天气怎么样？"
```

### 交互命令

在聊天中可以输入以下命令：

| 命令 | 说明 |
|------|------|
| `exit` / `quit` | 退出 Crabby |
| `clear` | 清除对话上下文 |
| `memory` | 查看当前记忆 |
| `skills` | 列出已安装的技能 |
| `help` | 显示帮助 |

### 心跳模式

Crabby 可以定时自动执行检查任务（类似 OpenClaw 的 Heartbeat）。

#### 手动运行

```powershell
.\crabby.ps1 -Heartbeat
```

#### 注册为 Windows 定时任务（每 30 分钟自动执行）

```powershell
.\install.ps1 -ScheduleHeartbeat
```

#### 自定义心跳检查项

编辑 `memory\heartbeat.md`：

```markdown
# Heartbeat Checks

- 检查磁盘空间，低于 10% 时警告
- 检查是否有新的 AI/科技新闻
- 检查今天的待办事项
```

Crabby 会根据检查项自动调用 LLM 执行检查，如果一切正常则不输出任何内容（NO_REPLY），有异常才会通知你。

#### 取消定时任务

```powershell
.\install.ps1 -Uninstall
```

## 🔧 内置工具

Crabby 内置了 15 个工具，LLM 可以自主调用：

### Shell & 系统
| 工具 | 说明 |
|------|------|
| `shell` | 执行 PowerShell 命令（持久会话，cwd/变量/模块跨命令保留） |
| `shell_confirm` | 确认执行被拦截的危险命令 |

### 文件操作
| 工具 | 说明 |
|------|------|
| `file_read` | 读取文件内容（支持 offset/lines 分页） |
| `file_write` | 写入文本文件（.md/.txt/.json/.py/.ps1/.html 等，自动创建目录） |
| `file_edit` | 查找替换文件中的文本 |
| `file_list` | 列出目录内容（支持递归） |
| `file_download` | 从 URL 下载文件到本地 |

### 文档创建
| 工具 | 说明 |
|------|------|
| `file_create_docx` | 创建 Word 文档（.docx），输入 Markdown 内容 |
| `file_create_xlsx` | 创建 Excel 表格（.xlsx），输入 JSON 数据 |
| `file_create_pptx` | 创建 PPT 演示文稿（.pptx），输入幻灯片数据 |
| `file_create_pdf` | 创建 PDF 文档，输入 Markdown 内容 |

### 网络 & 其他
| 工具 | 说明 |
|------|------|
| `web_fetch` | 抓取网页内容 |
| `web_search` | 搜索网页（DuckDuckGo） |
| `memory_save` | 保存信息到持久记忆 |
| `skill_run` | 运行已安装的技能 |

### 文档创建依赖

文档创建工具需要安装额外依赖，运行一键安装脚本：

```powershell
.\setup-tools.ps1
```

它会自动安装：
- **pandoc** — 用于生成 .docx / .pptx / .pdf
- **ImportExcel** PowerShell 模块 — 用于生成 .xlsx
- **wkhtmltopdf** — 用于 PDF 渲染

工具调用完全由 LLM 自主决策——你只需用自然语言说你想做什么，Crabby 会选择合适的工具执行。

#### 文档创建示例

```
You> 帮我写一份周报，保存到桌面
  ⚙️ Calling tool: file_create_docx
🦀 周报已保存到 C:\Users\Richard\Desktop\周报.docx！

You> 把上个月的销售数据做成Excel表格
  ⚙️ Calling tool: file_create_xlsx
🦀 销售数据表格已创建：C:\Users\Richard\Desktop\销售数据.xlsx

You> 做一个关于AI趋势的PPT，5页
  ⚙️ Calling tool: file_create_pptx
🦀 PPT已生成：C:\Users\Richard\Desktop\AI趋势.pptx（5页）
```

## 🧩 技能系统

技能是放在 `skills\` 目录下的 PowerShell 脚本，可以扩展 Crabby 的能力。

### 已内置技能

| 技能 | 说明 | 触发词 |
|------|------|--------|
| `system-info` | 获取系统信息（CPU、内存、磁盘、OS） | 系统信息、system info、电脑状态 |
| `weather-check` | 查询实时天气（wttr.in） | 天气、weather、温度 |

### 创建自定义技能

在 `skills\` 目录下新建 `.ps1` 文件：

```powershell
<#
.SkillName my-skill
.Description 我的自定义技能描述
.Trigger 触发词1|触发词2
#>
param([string]$Input = "")

# 你的技能逻辑
Write-Output "技能执行结果: $Input"
```

三个元数据字段：
- **SkillName** — 技能名称（必填）
- **Description** — 技能描述（必填）
- **Trigger** — 触发关键词，用 `|` 分隔（可选）

## 🎭 自定义人格

编辑 `config\SOUL.md` 来定义 Crabby 的性格：

```markdown
# Crabby Soul

You are Crabby 🦀, a personal AI assistant.
You are helpful, witty, and slightly snarky — like a clever crab who's always got your back.
You speak concisely and naturally, avoiding robotic phrases.
You adapt your tone to the user's mood.
```

你可以把它改成任何风格——严肃的、可爱的、毒舌的，随你喜欢。

## 💾 记忆系统

Crabby 的记忆完全基于 Markdown 文件：

```
memory/
├── MEMORY.md           # 持久记忆（LLM 可通过 memory_save 工具写入）
├── heartbeat.md        # 心跳检查项
└── conversations/      # 按日期存储的对话记录
    ├── 2026-06-14.md
    └── ...
```

- **MEMORY.md** — Crabby 会在对话中自动保存重要信息，启动时加载到上下文
- **conversations/** — 每天的对话自动归档，格式为 Markdown
- 你也可以手动编辑这些文件来添加或修改记忆

## 🌐 支持的 LLM 供应商

| 供应商 | Base URL | 免费额度 | 推荐模型 |
|--------|----------|----------|----------|
| 硅基流动 | `https://api.siliconflow.cn/v1` | 2000万 tokens | Qwen/Qwen3-8B |
| 智谱 | `https://open.bigmodel.cn/api/paas/v4/` | 2000万 tokens | glm-4-flash |
| DeepSeek | `https://api.deepseek.com/v1` | 200万 tokens/7天 | deepseek-chat |
| OpenAI | `https://api.openai.com/v1` | 付费 | gpt-4o-mini |
| 自定义 | 任意 OpenAI 兼容 API | — | — |

### 免费获取 API Key

1. **硅基流动**（推荐）：注册 [cloud.siliconflow.cn](https://cloud.siliconflow.cn/)，在「API 密钥」页面创建
2. **智谱**：注册 [open.bigmodel.cn](https://open.bigmodel.cn/)，在「API 密钥」页面创建

## 📁 项目结构

```
crabby-ai/
├── crabby.ps1              # 主入口（交互聊天/心跳模式）
├── crabby-gui.ps1          # 原生桌面界面（WPF，零依赖）
├── crabby-web.ps1          # Web UI 启动脚本
├── setup-tools.ps1        # 文档工具依赖安装（pandoc/ImportExcel/wkhtmltopdf）
├── install.ps1             # 安装向导 + 心跳调度注册
├── install-crabby.ps1      # 自解压安装脚本（无需 Git）
├── src/
│   ├── LLM.ps1             # LLM API 客户端（OpenAI 兼容）
│   ├── Memory.ps1          # 记忆与对话管理
│   ├── Tools.ps1           # 内置工具（Shell/文件/网页/记忆/技能）
│   ├── Skills.ps1          # 技能加载器
│   └── Server.ps1          # Web 服务器（HttpListener）
├── web/
│   └── index.html          # Web UI（单页应用）
├── config/
│   ├── SOUL.md             # 助手人格设定
│   ├── USER.md             # 用户画像
│   └── settings.json       # API 与模型设置
├── memory/
│   ├── MEMORY.md           # 持久记忆
│   ├── heartbeat.md        # 心跳检查项
│   └── conversations/      # 对话历史
├── skills/
│   ├── system-info.ps1     # 系统信息技能
│   └── weather-check.ps1   # 天气查询技能
├── .gitignore
├── LICENSE                 # MIT
└── README.md
```

## 🛡️ 安全说明

- API Key 存储在本地 `config\settings.json`，已被 `.gitignore` 排除
- 对话记录存储在本地 `memory\conversations\`，已被 `.gitignore` 排除
- Shell 工具具有完整的系统访问权限，危险命令（递归删除、格式化等）会被自动拦截并要求确认
- 建议不要在公共网络环境暴露 Crabby

## 🤝 与 OpenClaw 的对比

| 特性 | Crabby AI | OpenClaw |
|------|-----------|----------|
| 运行环境 | PowerShell / Windows 原生 | Node.js / WSL |
| 安装依赖 | 零依赖 | Node.js + npm |
| 消息渠道 | 终端交互 | WhatsApp/Telegram/Slack 等 |
| LLM 支持 | OpenAI 兼容 API | OpenAI/Anthropic/Ollama |
| 记忆系统 | Markdown 文件 | Markdown 文件 |
| 技能系统 | PowerShell 脚本 | JavaScript 插件 (ClawHub) |
| 心跳调度 | Windows 任务计划 | 内置 Gateway |
| 定位 | 轻量本地助手 | 全功能 Agent 平台 |

Crabby AI 不是 OpenClaw 的替代品，而是一个更轻量的选择——如果你只想在 Windows 上快速跑一个能干活的 AI 助手，不需要消息渠道集成和复杂的 Agent 框架，Crabby 就够了。

## 📄 License

MIT License
