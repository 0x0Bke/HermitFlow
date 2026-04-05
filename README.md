# HermitFlow

一个用 SwiftUI 写的 macOS 顶部悬浮岛应用，用来展示本机 Codex 会话状态、审批请求和窗口回焦入口。

## 当前能力

- 顶部居中的无边框悬浮窗口，跟随屏幕安全区和摄像头区域定位
- 三种展示状态：隐藏态、岛态、展开面板态
- 启动后默认轮询本机 `~/.codex` 数据，聚合最近会话状态
- 展示最近活跃会话、工作目录、运行状态和更新时间
- 检测审批请求，并提供 `Accept`、`Reject`、`Accept All` 操作
- 可将对应终端或桌面窗口带到前台
- 状态栏菜单支持显示/隐藏窗口、切换左侧 Logo
- 自动审批依赖 macOS“辅助功能”权限，未授权时会提示打开系统设置

## 工程结构

- `HermitFlow.xcodeproj`：Xcode 工程
- `DynamicCLIIsland/`：主应用源码
- `scripts/package.sh`：本地打包脚本
- `dist/`：打包输出目录

## 打开与运行

1. 用 Xcode 打开 [HermitFlow.xcodeproj](/Users/fuyue/Documents/HermitFlow/HermitFlow.xcodeproj)
2. 选择 `HermitFlow` scheme
3. 直接运行

应用启动后会默认进入本机 Codex 监控模式，读取以下本地数据源：

- `~/.codex/state_5.sqlite`
- `~/.codex/logs_1.sqlite`
- `~/.codex/sessions/`
- `~/.codex/.codex-global-state.json`
- `~/.codex/log/codex-tui.log`

如果这些文件不存在，界面会显示本地 Codex 状态不可用。

## 使用方式

- 单击悬浮岛：从隐藏态切到岛态，或从岛态展开到面板态
- 双击悬浮岛：从岛态或面板态切回隐藏态
- 展开面板后可查看最近会话、审批请求和窗口回焦入口
- 通过系统状态栏图标可显示/隐藏窗口、切换品牌 Logo、预览审批 UI

## 辅助功能权限

自动审批依赖 macOS“辅助功能”权限。未授权时，应用会在面板里显示提示，并提供打开系统设置入口。

## 打包

仓库内置了一个打包脚本：

```bash
./scripts/package.sh
```

默认生成 `Release` 版本，输出到：

- `/Users/fuyue/Documents/HermitFlow/dist/HermitFlow.app`
- `/Users/fuyue/Documents/HermitFlow/dist/HermitFlow.pkg`

如需打 `Debug` 包：

```bash
./scripts/package.sh Debug
```

## TODO
- 接入 Claude Code
