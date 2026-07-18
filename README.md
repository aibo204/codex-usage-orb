# Codex Usage Orb

一个极简的 macOS 桌面悬浮球，用来查看 Codex 剩余额度和工作状态。不需要反复打开 Codex 查额度，抬眼就能看到。

## 功能

### 极简的桌面悬浮球

- 始终置顶，可以拖到屏幕任意位置
- 支持多个桌面和全屏应用
- 只有一个悬浮球，不弹出多余卡片
- 绿色代表剩余额度，圆环长度就是剩余比例

### 自动显示 5 小时或每周额度

应用会读取 Codex 本地会话中的限额信息，自动选择应该显示的额度：

- 检测到 **5 小时限流**：显示 5 小时剩余额度
- 没有检测到 5 小时限流：自动显示每周剩余额度

近期 Codex 在部分情况下不再提供 5 小时限流信息，这时悬浮球会直接显示每周额度，不需要手动切换。

### Codex 工作时显示“工作中”

- 自动检测 Codex 是否正在执行任务
- 工作时显示蓝色动态圆环和“工作中”
- 蓝色圆环的长度仍然表示真实剩余额度
- 鼠标悬停可以查看任务标题、当前动作和运行时间
- 同时运行多个任务时，球内显示任务数量
- 任务完成或中断后发送 macOS 系统通知

### 数据只留在本机

- 不需要登录其他服务
- 不读取 `auth.json` 或 API Key
- 不上传 Codex 数据
- 不需要后台服务器

## 界面预览

| 工作中 | 5 小时剩余 | 每周剩余 |
| --- | --- | --- |
| ![工作中的悬浮球](docs/images/working-orb.png) | ![5 小时限额悬浮球](docs/images/usage-orb-5h.png) | ![每周限额悬浮球](docs/images/usage-orb-weekly.png) |

## 一键安装

打开“终端”，复制下面这一整行，粘贴后按回车：

```bash
curl -fsSL https://raw.githubusercontent.com/aibo204/codex-usage-orb/main/install.sh | bash
```

命令会自动下载源码、在你的 Mac 上本机编译、安装到个人“应用程序”目录并启动。源码构建通常不会触发下载版应用的首次 Gatekeeper 拦截。

如果系统提示安装 Apple 命令行工具，请完成安装，然后再运行一次上面的命令。

安装位置：

```text
~/Applications/Codex Usage Orb.app
```

以后重新启动：

```bash
open "$HOME/Applications/Codex Usage Orb.app"
```

再次执行一键安装命令可以更新到最新版本。

## DMG 安装

也可以从 [Releases](../../releases) 下载最新 DMG，把 `Codex Usage Orb.app` 拖入“应用程序”。

免费发布版本没有 Apple Developer ID 公证。首次打开如果被 macOS 拦截，请按住 Control 点击应用，选择“打开”。不要关闭 Gatekeeper。

## 使用方法

- 拖动悬浮球：移动位置
- 鼠标悬停：查看当前任务信息
- 右键悬浮球：立即刷新或退出
- 左键点击：不执行操作，避免误触

悬浮球不会显示在 Dock 中。

## 系统要求

- macOS 12 或更高版本
- Apple Silicon 或 Intel Mac
- 本机安装并使用过 Codex
- 首次启动时允许系统通知

## 数据与隐私

应用只读取当前用户目录中的：

- `~/.codex/sessions`：任务生命周期、进度与用量事件
- `~/.codex/session_index.jsonl`：本地任务标题

为了避免在界面和通知中暴露隐私，进度摘要会清理本地文件路径并限制长度。

Codex Usage Orb 是本地日志观察器，不是 OpenAI 官方应用。Codex 日志格式未来发生变化时，解析逻辑可能需要同步更新。

## 从源码构建

```bash
git clone https://github.com/aibo204/codex-usage-orb.git
cd codex-usage-orb
chmod +x build-app.sh
./build-app.sh
open "dist/Codex Usage Orb.app"
```

构建脚本会生成同时支持 `arm64` 与 `x86_64` 的 Universal 2 应用。

## 许可证

[MIT](LICENSE)
