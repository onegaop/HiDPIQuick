# HiDPI Quick

一个原生 macOS 菜单栏工具，用来确认当前显示器是否真正运行在 2x HiDPI，并快速切换可用的 HiDPI 分辨率。

项目使用 SwiftUI、AppKit 和 CoreGraphics 从零实现，不基于 RDM，也不包含 One Switch 的源码。界面和功能组织参考了 macOS 系统设置与同类菜单栏工具的通用交互。

## 功能

- 显示逻辑分辨率、2x 渲染分辨率和刷新率
- 只列出真正满足 2x backing、且适合桌面使用的 HiDPI 模式
- 紧凑菜单优先显示当前分辨率；多屏时可选择目标屏幕，其他 HiDPI 模式按需展开
- 选择分辨率后先关闭菜单并直接应用，重新打开可查看最新状态
- 快捷控制分为常驻开关（防休眠、深色模式等）和即时操作（屏保、关闭显示器）
- 自动跟踪显示器连接和分辨率变化

## 实现

- `DisplayManager`：枚举活动显示器和可用 2x HiDPI 模式，使用 CoreGraphics 配置分辨率
- `AppViewModel`：管理分辨率切换、状态验证和辅助功能播报
- `SystemController`：在后台执行系统开关和快捷动作，避免阻塞菜单栏界面
- `ContentView`：原生 SwiftUI 弹窗界面，支持系统浅色/深色外观

## 构建

需要 Apple Silicon Mac、macOS 13 或更新版本，以及可用的 Xcode Command Line Tools。

```bash
./scripts/build_dmg.sh
```

构建结果位于 `build/HiDPI-Quick.dmg`，仅包含 Apple Silicon `arm64` 可执行文件。App 使用本机临时签名，首次打开时 macOS 可能要求确认；深色模式第一次切换会请求控制“系统事件”的自动化权限。

## 许可证

[MIT](LICENSE)
