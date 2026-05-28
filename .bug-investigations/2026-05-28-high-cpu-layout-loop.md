# 主面板 SwiftUI 布局循环卡死
创建时间: 2026-05-28
状态: 已解决

## 症状
OPCCompanion 进程 PID 68896 卡住，`ps aux` 显示 CPU 100.3%，状态 R，累计 CPU 时间 60:00.95，物理内存 24.1G。用户要求重启进程并定位卡住原因。

## 数据流路径
HUDPanel -> NSVisualEffectView -> NSHostingView<ContentView> -> ContentView ZStack -> MainTabView / ChatView / InputBar。采样显示主线程长期停留在 SwiftUI/SwiftUICore/AttributeGraph 的 ViewGraph flush 和 layout sizeThatFits / placeChildren 路径。

## 已排除的假设
- [x] AI 请求或网络阻塞: sample 栈没有 ChatEngine/URLSession/Process 子进程路径，主线程在 SwiftUI layout。
- [x] 多进程版本冲突: 重启前只有 `/Users/shiye/Projects/OPC 伴侣/OPCCompanion.app/Contents/MacOS/OPCCompanion` 一个进程。
- [x] 普通空闲: 物理内存 24.1G 且 CPU 100.3%，不是正常 idle。

## 当前假设
最高嫌疑是 12:13 圆角修复直接对 `NSHostingView` 本体设置 `wantsLayer = true`、`layer.cornerRadius`、`layer.masksToBounds = true`。`NSHostingView` 是 SwiftUI/AppKit 边界对象，直接给它加 AppKit layer mask 可能让 SwiftUI 的 ViewGraph/layout 与 AppKit 裁切刷新互相触发，形成布局循环。采样中的 `GraphHost.flushTransactions`、`AttributeGraph`、`_ZStackLayout.sizeThatFits`、`PlatformTextFieldAdaptor._overrideSizeThatFits` 与这个判断一致。

## 修复尝试记录
### 尝试 1 (当前会话, 2026-05-28)
- 方案: 不再直接裁 `NSHostingView` 本体，改为在它外面包一层普通 `NSView` 圆角裁切容器；同步圆角时同步这个 clip container。
- 结果: `swift test` 85/85 通过；`./build.sh` 成功；已重启 app。新进程 PID 4834 启动 5 秒后 CPU 4.9%、RSS 约 107MB；再观察 15 秒后 CPU 0.3%、RSS 约 107MB。
- 结论: 卡死原因高度确定为直接对 `NSHostingView` 本体做 AppKit layer mask，引发 SwiftUI layout/display 循环。改为外层普通 NSView 裁切后，启动后未复现 100% CPU / 24GB RSS。
