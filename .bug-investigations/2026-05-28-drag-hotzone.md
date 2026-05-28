# 主面板拖动热区完全失效
创建时间: 2026-05-28
状态: 已修复（采用方案 X，待用户验证）

## 症状
- 之前 `panel.isMovableByWindowBackground = true` → 整个面板都能拖（过大）
- 改成 `false` + 在顶部 TabBar `.background(WindowDragHandle())` 放 NSView (`mouseDownCanMoveWindow = true`)
- 后又改成 ZStack 顶部 `.frame(width: 520, height: 10)` 绝对定位
- **两种实现都不工作 — 现在面板完全不能拖**

## 数据流路径
1. AppKit 鼠标事件 → NSPanel → contentView (shadowWrapper) → NSVisualEffectView → NSHostingView → SwiftUI ContentView → ZStack → MainTabView → VStack → NewTabBar.background(WindowDragHandle())
2. AppKit 在 mouseDown 时调用 `hitTest(_:)` 找到目标 view，然后检查它的 `mouseDownCanMoveWindow`，若 true 则启动拖窗

## 已排除的假设
（待验证后填充）

## 当前 5 个嫌疑（按 task spec）
- B1: SwiftUI NSViewRepresentable 包的 NSView 的 `mouseDownCanMoveWindow` 在 SwiftUI hit-test 路径下不被 AppKit 识别（最高嫌疑）
- B2: `panel.isMovableByWindowBackground = false` 之后整个 panel 都不能拖（即使有子 view mouseDownCanMoveWindow=true）
- B3: WindowDragHandle frame(520, 10) 太小或定位错位
- B4: ZStack 内部 hit-test 路由让其它 view 先消费事件
- B5: NSPanel styleMask 不含 .titled / .nonactivatingPanel 影响拖窗识别

## 关键事实
- panel styleMask = `[.fullSizeContentView]`（不含 .titled，不含 .nonactivatingPanel）
- panel.isMovableByWindowBackground = false
- contentView 层级：shadowWrapper(NSView) → NSVisualEffectView → NSHostingView(SwiftUI)
- WindowDragHandle 当前放在 NewTabBar.background()，不是 ZStack 绝对定位（这是任务里描述的"第一种"实现，但当前代码用的是这个）

## 调查策略
1. 验证 B1：用 NSEvent.addLocalMonitorForEvents 拦截 leftMouseDown，看事件能否到达 AppKit 层，打印坐标
2. 如果事件能拿到 → 用方案 X（NSEvent.localMonitor + panel.performDrag）绕开 SwiftUI hit-test
3. 实现细分热区：胶囊本身（中央 240-520 横向区间，顶部 12-48 纵向）不可拖；其余顶部 60pt 可拖

## 修复方案（先验证再决定）
方案 X：NSEvent.localMonitor 拦截 leftMouseDown
- 优势：绕开 SwiftUI hit-test，直接在 NSPanel 层处理
- 实现：在 AppDelegate 加 localMonitor，判断 location 是否在 hotZone，是则调用 panel.performDrag(with:) 并返回 nil 消费事件
- hotZone 定义：panel 顶部 60pt 内（y >= panel.height - 60），且避开胶囊本身（胶囊估算 panel 中央 280pt 宽：x ∈ [240, 520]）
- 边缘情况：胶囊上方 12pt padding 全宽可拖，确保用户能在 panel 顶部边缘"贴边"也能拖

## 修复尝试记录
### 尝试 1 (会话 2026-05-28) — 已实施
- 根因坐实：B1（SwiftUI NSHostingView 吞掉鼠标事件，NSView 的 mouseDownCanMoveWindow 完全不工作）
- 方案：方案 X（NSEvent.addLocalMonitorForEvents + panel.performDrag）
- 实施内容：
  1. AppDelegate 加 `dragHotZoneMonitor`，在 applicationDidFinishLaunching 启动
  2. `setupDragHotZoneMonitor()` 监听 .leftMouseDown，event.window === panel 时检查 hotZone
  3. hotZone 定义：panel 顶部 72pt 之内（TabBar 区域），但避开胶囊本体（中央 ±150pt 横向、顶部 12-58pt 纵向）
  4. 命中 hotZone 时调用 `panel.performDrag(with: event)` 并返回 nil 消费事件
  5. 删除 MainTabView 中无效的 WindowDragHandle/DragHandleNSView
  6. applicationWillTerminate 清理 dragHotZoneMonitor
- 验证方式：用户复现
  - 按 TabBar 区域（胶囊上方 padding / 胶囊左右两侧 / 胶囊下方 padding）能拖动 panel
  - 按胶囊本体（聊聊/历史/设置三按钮）不拖动，正常切换 Tab
  - 按 ChatView 任意位置（消息流、输入框等）不拖动
  - dlog 输出 `[DRAG] mouseDown at (x, y) — in hot zone, performDrag` 或 `in capsule body, skip drag`
- 编译/测试：swift build ✅、swift test (76 tests passed) ✅、./build.sh ✅
