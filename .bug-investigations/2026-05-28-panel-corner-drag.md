# 面板圆角直角残影与拖动热区
创建时间: 2026-05-28
状态: 已解决

## 症状
1. 面板圆角外仍有一圈浅色直角残影，之前两次修复后仍未完全消失。
2. 面板拖动热区被反馈过大，调整后又表现为实际可用热区被删掉或不在预期位置。

## 数据流路径
AppDelegate.setupPanel 创建 HUDPanel -> shadowWrapper 承载阴影 -> NSVisualEffectView 承载 material 和 NSHostingView -> ContentView 绘制主题背景和 MainTabView -> MainTabView 顶部导航区域挂载 WindowDragHandle。

## 已排除的假设
- [x] 运行错版本: `ps aux` 确认 PID 50251 是 `/Users/shiye/Projects/OPC 伴侣/OPCCompanion.app/Contents/MacOS/OPCCompanion`。
- [x] 只需要关闭 AppKit 默认阴影: 当前代码已 `panel.hasShadow = false` 并改用 shadowWrapper，但问题仍被用户复现。
- [x] 只需要关闭全窗口背景拖动: 当前代码已 `panel.isMovableByWindowBackground = false`，但 `WindowDragHandle` 被挂在整条顶部导航行背景上，热区仍不精确。

## 当前假设
圆角问题不是单一 NSVisualEffectView mask，而是 SwiftUI 根内容没有整体裁切：`ContentView` 只裁了背景层和 burst 层，MainTabView/底部 material 等内容仍可能在根视图边界形成直角残影。拖动问题是热区挂载层级错误：`.frame(maxWidth: .infinity).background(WindowDragHandle())` 把整条顶部导航行变成可拖区域，既过大，也容易和按钮 hit-test 行为混在一起。

## 修复尝试记录
### 尝试 1 (当前会话, 2026-05-28)
- 方案: `ContentView` 根层整体 `clipShape` 到主题圆角；`MainTabView` 移除整行 background 拖动手柄，改成顶部居中的 520x10 小拖动条。
- 结果: `swift test` 85/85 通过；`./build.sh` 成功；已杀掉 PID 50251 并启动新 bundle，当前 PID 53334。
- 结论: 圆角修复应落在 SwiftUI 根内容裁切层；拖动热区应是显式小条，而不是整条导航背景。
