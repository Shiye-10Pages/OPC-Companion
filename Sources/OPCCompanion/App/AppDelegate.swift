import AppKit
import SwiftUI
import Combine
import Foundation
import UserNotifications
import Carbon.HIToolbox

// 兼容旧调用点：全部转发到 OPCLogger
func dlog(_ message: String) {
    OPCLogger.shared.log(.info, "legacy", message)
}

final class RedDotView: NSView {}

/// 在 styleMask 不含 .titled 的 NSPanel 里，AppKit 不会自动把 Edit 菜单
/// 的 cut:/copy:/paste:/selectAll: 路由到 SwiftUI TextField/SecureField。
/// 我们在 panel 层显式重派发，保证粘贴在 SecureField（设置页 API Key 等）里也工作。
@MainActor
private func forwardStandardEditCommands(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command),
          !event.modifierFlags.contains(.option),
          !event.modifierFlags.contains(.control) else { return false }
    let chars = event.charactersIgnoringModifiers ?? ""
    switch chars {
    case "v":
        return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    case "c":
        return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    case "x":
        return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
    case "a":
        return NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
    case "z":
        let sel: Selector = event.modifierFlags.contains(.shift)
            ? Selector(("redo:")) : Selector(("undo:"))
        return NSApp.sendAction(sel, to: nil, from: nil)
    default:
        return false
    }
}

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if forwardStandardEditCommands(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if forwardStandardEditCommands(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!

    /// 给 NSVisualEffectView 用的圆角 mask image。capInsets 让小图可拉伸到任意尺寸。
    /// material 的 backdrop blur 必须用 maskImage 才能正确按圆角裁切。
    static func makeRoundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = max(cornerRadius * 2 + 1, 3)
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius,
                                     bottom: cornerRadius, right: cornerRadius)
        img.resizingMode = .stretch
        return img
    }

    var panel: NSPanel?
    /// 主面板的 visualEffectView 引用，便于主题切换时同步 layer.cornerRadius
    weak var panelEffectView: NSVisualEffectView?
    /// 主面板 SwiftUI 宿主 view 外层的 AppKit 裁切容器。
    /// 不直接裁 NSHostingView 本体，避免 SwiftUI/ViewGraph 与 AppKit layer mask
    /// 互相触发布局刷新；圆角裁切由普通 NSView 容器承担。
    weak var panelHostingLayerView: NSView?
    var quickCapturePanel: NSPanel?
    /// Quiet Field 新前门预览面板（v2 原型，独立于主面板与 Quick Capture，零侵入）
    var quietFieldPreviewPanel: NSPanel?
    /// 方案 B 展开过渡中：抑制折叠 bar 的 resignKey 自动关闭，让淡出动画收尾
    /// （否则主面板抢 key → bar resignKey → orderOut 立即截断 A 过渡的淡出）。
    private var isExpandingToMain = false
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    var hotkeyMonitor: Any?
    var localHotkeyMonitor: Any?
    /// 拖动热区监视器：SwiftUI NSHostingView 会吞掉鼠标事件，导致 NSView 子 view
    /// 的 mouseDownCanMoveWindow 完全不工作。改用 NSEvent.addLocalMonitorForEvents
    /// 在 AppKit 事件路径上拦截 leftMouseDown，命中热区时调用 panel.performDrag。
    var dragHotZoneMonitor: Any?
    var hotkeyDownTime: Date?
    var isLongPressTriggered = false
    private var lastSpaceKeyDownAt: Date = .distantPast
    private var lastQuickCaptureAt: Date = .distantPast

    // 顶部胶囊导航的拖动热区参数（panel 局部坐标，原点在左下）
    // panel 高 620，宽 760。NewTabBar 在 ContentView 顶部，padding(.top, 12) + bar(~46) + padding(.bottom, 14) = 72pt
    // 胶囊本身在屏幕居中，宽度约 280pt → x ∈ [240, 520] 是胶囊范围（不拖，让胶囊响应点击）
    private static let dragHotZoneTopHeight: CGFloat = 72   // 顶部 72pt 是 TabBar 区域
    private static let dragHotZoneCapsuleHalfWidth: CGFloat = 190  // 场所胶囊 + 设置齿轮，中心 ±190pt = 380pt 总宽（保守留点 margin）

    var state = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    private var statusTimer: Timer?
    private var scheduledCheckTimer: Timer?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dlog("===========================================")
        dlog("AppDelegate: applicationDidFinishLaunching START")
        dlog("===========================================")
        
        dlog("[DIAG] NSApplication.shared: \(NSApplication.shared)")
        dlog("[DIAG] NSApplication.shared.isActive: \(NSApplication.shared.isActive)")

        setupMainMenu()
        dlog("[DIAG] Main menu setup completed")
        
        setupStatusItem()
        dlog("[DIAG] StatusItem setup completed")
        
        setupPanel()
        dlog("[DIAG] Panel setup completed")
        
        // 启动时不自动显示面板
        
        setupHotkey()
        dlog("[DIAG] Hotkey setup completed")
        dlog("[DIAG] hotkeyMonitor: \(String(describing: hotkeyMonitor))")

        setupDragHotZoneMonitor()
        dlog("[DIAG] Drag hot zone monitor setup completed")

        startScheduledTaskCheck()
        dlog("[DIAG] Timer setup completed")

        setupStateObservers()
        dlog("[DIAG] Observers setup completed")

        // 监听 Space 切换：用户换到另一个桌面 Space 时直接关闭面板，避免闪烁
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        dlog("===========================================")
        dlog("AppDelegate: applicationDidFinishLaunching END")
        dlog("===========================================")
        
        dlog("[DIAG] FINAL - statusItem: \(statusItem != nil)")
        dlog("[DIAG] FINAL - panel: \(panel != nil)")
        dlog("[DIAG] FINAL - hotkeyMonitor: \(hotkeyMonitor != nil)")
    }

    func createMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let quitItem = NSMenuItem(
            title: "退出 OPC 伴侣",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu

        let cutItem = NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(pasteItem)

        editMenu.addItem(NSMenuItem.separator())

        let selectAllItem = NSMenuItem(title: "全选", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(selectAllItem)

        return mainMenu
    }

    private func setupMainMenu() {
        NSApplication.shared.mainMenu = createMainMenu()
    }

    private func setupStatusItem() {
        dlog("[DIAG] setupStatusItem: START")
        
        let systemBar = NSStatusBar.system
        dlog("[DIAG] NSStatusBar.system obtained")
        
        statusItem = systemBar.statusItem(withLength: NSStatusItem.variableLength)
        dlog("[DIAG] statusItem created")
        
        if let button = statusItem?.button {
            dlog("[DIAG] statusItem button obtained")
            let image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "OPC 伴侣")
            image?.isTemplate = true
            button.image = image

            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading

            button.isEnabled = true
            button.isHidden = false
            
            dlog("[DIAG] button.isEnabled: \(button.isEnabled)")
            dlog("[DIAG] button.isHidden: \(button.isHidden)")
            dlog("[DIAG] button.frame: \(button.frame)")
            dlog("[DIAG] button.title: '\(button.title)'")
            dlog("[DIAG] button.image: \(String(describing: button.image))")
            
            button.toolTip = "点击显示面板 (Option+Space)"
            
            // 尝试让按钮可点击 - 添加鼠标事件
            dlog("[DIAG] Setting up button click handler...")
        } else {
            dlog("[ERROR] statusItem button is nil!")
        }
        
        dlog("[DIAG] setupStatusItem: END")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        dlog("===========================================")
        dlog("[EVENT] statusItemClicked!")

        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            let menu = createStatusItemMenu()
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
            return
        }

        showPopover()
    }

    private func showPopover() {
        dlog("[DIAG] showPopover called")

        // 每次都创建新的 Popover 确保内容刷新
        let popoverContent = StatusBarPopoverView()
            .environmentObject(state)

        let newPopover = NSPopover()
        newPopover.contentSize = NSSize(width: 340, height: 420)
        newPopover.behavior = .transient
        newPopover.contentViewController = NSHostingController(rootView: popoverContent)

        // 关闭旧的
        popover?.close()

        // 保存新的
        popover = newPopover
        dlog("[DIAG] Popover created fresh")

        // 显示前先激活 app，否则 popover 弹出时是非 key 状态（灰色/失焦），要用户再点一次才"点亮"
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 显示
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            dlog("[DIAG] Popover shown")
        }
    }

    private func setupPanel() {
        dlog("[DIAG] setupPanel: START")
        
        dlog("[DIAG] Creating ContentView...")
        let contentView = ContentView()
            .environmentObject(state)
        
        dlog("[DIAG] Creating NSHostingView...")
        let hostingView = NSHostingView(rootView: contentView)
        dlog("[DIAG] hostingView frame: \(hostingView.frame)")
        
        // 防止创建多个 panel
        if self.panel != nil {
            dlog("[DIAG] Panel already exists, reusing...")
            return
        }

        dlog("[DIAG] Creating NSPanel...")
        // .fullSizeContentView 单独使用（不加 .titled 避免启动卡死，不加 .nonactivatingPanel 保证中文输入法可用）
        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        dlog("[DIAG] Configuring panel properties...")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // 关闭整个 panel 背景可拖。改由 SwiftUI 顶部胶囊区域的 WindowDragHandle
        // 提供精确热区（mouseDownCanMoveWindow=true），其它区域不响应拖动。
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        // 不加入所有 Space：用户切换到其他 Space 时面板应消失而不是闪现
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // 恢复 panel 系统级 shadow：现在 hostingView + effectView 都圆角裁切了，
        // panel 的 alpha shape 是圆角的（圆角外像素 alpha = 0）。
        // NSPanel.hasShadow=true 会按 alpha 不透明区域画 shadow，penumbra 完全
        // 在 panel 外。比手画 shadowWrapper.layer.shadow 更干净（不在 panel 内
        // 留残留 5-9% alpha penumbra）。
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let initialRadius = ThemeProvider.shared.current.panelCornerRadius

        // shadowWrapper：保留作为 effectView/hostingView 的容器，但不再画 shadow。
        // shadow 由 panel.hasShadow=true 由 macOS 系统级按 alpha shape 自动绘制。
        let shadowWrapper = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 620))
        shadowWrapper.wantsLayer = true
        // 显式透明：杜绝 wrapper 自身在圆角外漏色（A2 防御）
        shadowWrapper.layer?.backgroundColor = NSColor.clear.cgColor
        shadowWrapper.layer?.masksToBounds = false
        shadowWrapper.autoresizingMask = [.width, .height]

        let effectView = NSVisualEffectView(frame: shadowWrapper.bounds)
        effectView.material = .popover          // 比 hudWindow 更轻透，接近 Liquid Glass
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        // 初始圆角 = 当前主题 panelCornerRadius；后续主题切换会通过 syncPanelCornerRadius 跟随
        // 关键：NSVisualEffectView 的 material 是系统级 backdrop blur，layer.cornerRadius
        // 只能裁普通 layer 内容裁不了 material；必须用 maskImage 才能让 material 真正按
        // 圆角裁切。否则圆角外一圈仍渲染 material，视觉上呈现"圆角外的浅色直角边"。
        effectView.maskImage = Self.makeRoundedMaskImage(cornerRadius: initialRadius)
        effectView.layer?.cornerRadius = initialRadius
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        self.panelEffectView = effectView

        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        // 用普通 NSView 做圆角裁切容器。不要直接给 NSHostingView 本体加 layer mask：
        // NSHostingView 是 SwiftUI/AppKit 边界，直接 masksToBounds 可能触发 SwiftUI
        // layout/display 循环。容器裁切能挡住圆角外漏色，同时不干预 SwiftUI 自身布局。
        let hostingClipView = NSView(frame: effectView.bounds)
        hostingClipView.wantsLayer = true
        hostingClipView.layer?.cornerRadius = initialRadius
        hostingClipView.layer?.masksToBounds = true
        hostingClipView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingClipView.autoresizingMask = [.width, .height]
        self.panelHostingLayerView = hostingClipView

        hostingView.frame = hostingClipView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingClipView.addSubview(hostingView)
        effectView.addSubview(hostingClipView)
        shadowWrapper.addSubview(effectView)

        dlog("[DIAG] Setting panel contentView...")
        panel.contentView = shadowWrapper
        
        self.panel = panel
        
        dlog("[DIAG] Panel configured:")
        dlog("[DIAG]   - isVisible: \(panel.isVisible)")
        dlog("[DIAG]   - frame: \(panel.frame)")
        dlog("[DIAG]   - level: \(panel.level)")
        dlog("[DIAG]   - contentView set: \(panel.contentView != nil)")
        
        dlog("[DIAG] setupPanel: END")
    }

    private func setupHotkey() {
        dlog("[DIAG] setupHotkey: START")

        // 全局热键用 Carbon（RegisterEventHotKey），不需要辅助功能权限
        registerCarbonHotkeys()

        // Local monitor 保留：Esc 关面板 / Cmd+D 关面板 / Cmd+=/-/0 微调字号（只在 app 内生效）
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.modifierFlags.contains(.command) {
                // Cmd+D 关面板
                if event.keyCode == 2 {
                    dlog("[LOCAL-HOTKEY] Cmd+D detected - closing panel!")
                    DispatchQueue.main.async { AppDelegate.shared?.hidePanel() }
                    return nil
                }
                // Cmd+= / Cmd++ / Cmd+- / Cmd+0 字号微调（气泡 + 输入框 + 面板）
                switch event.charactersIgnoringModifiers {
                case "=", "+":
                    DispatchQueue.main.async { AppState.shared.adjustFontScale(0.1) }
                    return nil
                case "-":
                    DispatchQueue.main.async { AppState.shared.adjustFontScale(-0.1) }
                    return nil
                case "0":
                    DispatchQueue.main.async { AppState.shared.resetFontScale() }
                    return nil
                default:
                    break
                }
            }
            if event.keyCode == 53 {
                // 中文 IME 组合输入期间，Esc 是取消候选词，不能被拦截关面板
                if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.hasMarkedText() {
                    return event
                }
                if AppDelegate.shared?.quietFieldPreviewPanel?.isVisible == true {
                    dlog("[LOCAL-HOTKEY] Escape - closing Quiet Field preview!")
                    DispatchQueue.main.async { AppDelegate.shared?.hideQuietFieldPreview() }
                    return nil
                }
                if AppDelegate.shared?.quickCapturePanel?.isVisible == true {
                    dlog("[LOCAL-HOTKEY] Escape - closing quick capture!")
                    DispatchQueue.main.async { AppDelegate.shared?.hideQuickCapture() }
                    return nil
                }
                if AppDelegate.shared?.panel?.isVisible == true {
                    dlog("[LOCAL-HOTKEY] Escape - closing panel!")
                    DispatchQueue.main.async { AppDelegate.shared?.hidePanel() }
                    return nil
                }
            }
            return event
        }
        dlog("[DIAG] setupHotkey: END")
    }

    /// 拖动热区：仅在 panel 顶部 TabBar 区域内（且避开胶囊本身）启动 panel 拖动。
    ///
    /// 背景：原本想用 SwiftUI NSViewRepresentable 包 NSView 配合 mouseDownCanMoveWindow=true。
    /// 实测在 NSHostingView 包裹下完全失效——SwiftUI 自己的 hit-test 处理掉了鼠标事件，
    /// AppKit 检查 mouseDownCanMoveWindow 的代码路径走不到。
    /// 改用 NSEvent.addLocalMonitorForEvents 在 SwiftUI 之前的事件路径上拦截 leftMouseDown，
    /// 命中热区时调用 panel.performDrag(with:) 并返回 nil 消费事件。
    private func setupDragHotZoneMonitor() {
        dragHotZoneMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self = self,
                  let p = self.panel,
                  event.window === p else {
                return event
            }

            let location = event.locationInWindow  // panel 局部坐标，原点左下
            let panelHeight = p.frame.height
            let panelWidth = p.frame.width

            // 顶部 72pt 之外不响应（让 ChatView / 列表 / 输入框等正常工作）
            let topEdgeY = panelHeight - Self.dragHotZoneTopHeight
            guard location.y >= topEdgeY else {
                return event
            }

            // 胶囊本身区域：panel 中央水平方向 ±dragHotZoneCapsuleHalfWidth，且竖直方向避开胶囊本体
            // 胶囊估算 y 范围：从 panel 顶部往下 12pt（top padding）后开始，高度约 46pt
            // 即胶囊本体 y ∈ [panelHeight - 12 - 46, panelHeight - 12]
            let centerX = panelWidth / 2
            let inCapsuleHorizontal = abs(location.x - centerX) <= Self.dragHotZoneCapsuleHalfWidth
            let capsuleTop = panelHeight - 12
            let capsuleBottom = panelHeight - 12 - 46
            let inCapsuleVertical = location.y <= capsuleTop && location.y >= capsuleBottom

            if inCapsuleHorizontal && inCapsuleVertical {
                // 胶囊本体：让 SwiftUI 处理点击切换 Tab
                dlog("[DRAG] mouseDown at (\(Int(location.x)), \(Int(location.y))) — in capsule body, skip drag")
                return event
            }

            dlog("[DRAG] mouseDown at (\(Int(location.x)), \(Int(location.y))) — in hot zone, performDrag")
            p.performDrag(with: event)
            return nil  // 消费这次 mouseDown，避免 SwiftUI 同时处理（performDrag 接管后续 mouseDragged/mouseUp）
        }
    }

    /// 设置页「重新注册热键」按钮调用：先全量注销 Carbon 热键，再重新注册（不动 local monitor）。
    func reregisterHotkeys() {
        OPCLogger.shared.log(.info, "hotkey", "[reregister] manual trigger - unregistering all carbon hotkeys and reinstalling")
        CarbonHotkeyManager.shared.unregisterAll()
        HotkeyHealthMonitor.shared.stop()
        registerCarbonHotkeys()
    }

    private func registerCarbonHotkeys() {
        let optionMod = UInt32(optionKey)

        let spaceID = CarbonHotkeyManager.shared.register(
            keyCode: 49, modifiers: optionMod,
            onPress: { [weak self] in self?.handleOptSpacePress() }
        )
        if spaceID == nil {
            OPCLogger.shared.log(.error, "hotkey", "Opt+Space (keyCode 49) 注册失败 — 该组合可能已被系统占用（macOS 默认: 输入法切换）。请到「系统设置 → 键盘 → 键盘快捷键 → 输入源」检查是否启用了 Option+Space。")
        }

        OPCLogger.shared.log(.info, "hotkey", CarbonHotkeyManager.shared.currentRegistrationsSnapshot())

        HotkeyHealthMonitor.shared.start()
    }

    // MARK: - Carbon hotkey handlers

    private func handleOptSpacePress() {
        let now = Date()
        if now.timeIntervalSince(lastSpaceKeyDownAt) < 0.2 { return }
        lastSpaceKeyDownAt = now
        // 入口模式分流：classic = 旧三胶囊主面板；quietField（默认）= 新前门。即时生效，无需重注册。
        if state.config.entryMode == "classic" {
            togglePanel()
        } else if panel?.isVisible == true {
            // quietField 已展开成主面板（方案 B）→ 再按热键收起主面板
            hidePanel()
        } else {
            toggleQuietFieldPreview()
        }
    }

    // 旧的 NSEvent global monitor 版本 handleHotkey 已被 Carbon 版替换

    private func startScheduledTaskCheck() {
        dlog("[DIAG] startScheduledTaskCheck: START")

        requestNotificationAuthorization()
        state.checkScheduledTasks()

        // 启动即做一次：跨日归档 + 跨周归档 + 随手记 48h 过期
        InboxService.shared.expirePendingNotesOlderThan48h(state: state)
        Task { @MainActor in
            await SessionArchiveService.shared.checkRolloverNeeded()
            await WeeklyArchiveService.shared.checkWeeklyRolloverIfNeeded()
        }

        scheduledCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                AppState.shared.checkScheduledTasks()
                AppState.shared.checkProgressPing()
                InboxService.shared.expirePendingNotesOlderThan48h(state: AppState.shared)
                Task { @MainActor in
                    await SessionArchiveService.shared.checkRolloverNeeded()
                    await WeeklyArchiveService.shared.checkWeeklyRolloverIfNeeded()
                }
            }
        }

        dlog("[DIAG] scheduledCheckTimer created")
        dlog("[DIAG] startScheduledTaskCheck: END")
    }

    private func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            dlog("[DIAG] Notification auth granted=\(granted) error=\(String(describing: error))")
        }
    }

    private func setupStateObservers() {
        dlog("[DIAG] setupStateObservers: START")

        // 任何状态变化都刷新菜单栏外观
        let pendingNotesPub = state.$notes.map { notes in
            notes.filter { $0.status == .pending }.count
        }
        state.$menuBarStatus
            .combineLatest(state.$hasUnreadReminders, pendingNotesPub)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status, hasUnreadReminder, _ in
                self?.updateStatusItemAppearance(
                    status: status,
                    hasUnreadReminder: hasUnreadReminder
                )
            }
            .store(in: &cancellables)

        updateStatusItemAppearance(
            status: state.menuBarStatus,
            hasUnreadReminder: state.hasUnreadReminders
        )

        // 每秒刷新菜单栏文字（展示正在进行任务名 + 倒计时）
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItemTitle() }
        }
        refreshStatusItemTitle()

        dlog("[DIAG] setupStateObservers: END")
    }

    private func refreshStatusItemTitle() {
        guard let button = statusItem?.button else { return }

        let text: String
        let color: NSColor
        let weight: NSFont.Weight

        if let active = state.activeTask,
           active.status == .inProgress,
           let remaining = active.remainingSeconds {
            let truncated: String = active.title.count > 8
                ? String(active.title.prefix(7)) + "…"
                : active.title
            let mm = remaining / 60
            let ss = remaining % 60
            text = " \(truncated) \(String(format: "%02d:%02d", mm, ss))"
            switch state.menuBarStatus {
            case .warning:
                color = .systemYellow
                weight = .semibold
            case .overtime:
                color = .systemRed
                weight = .bold
            default:
                color = .labelColor
                weight = .regular
            }
        } else if state.unreadNoteCount > 0 {
            let noteCount = state.unreadNoteCount > 9 ? "9+" : "\(state.unreadNoteCount)"
            text = " 浮念 \(noteCount)"
            color = .systemYellow
            weight = .medium
        } else if state.hasUnreadReminders {
            text = " 待看"
            color = .systemRed
            weight = .medium
        } else {
            text = " 静场"
            color = .secondaryLabelColor
            weight = .regular
        }

        let attributed = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: weight)
        ])
        button.attributedTitle = attributed
    }

    private func updateStatusItemAppearance(status: MenuBarStatus, hasUnreadReminder: Bool) {
        guard let button = statusItem?.button else {
            dlog("[STATUS] updateStatusItemAppearance skipped — button is nil")
            return
        }

        let symbolName = "bubble.left.fill"
        if let color = Self.tintColor(for: status) {
            let image = Self.tintedStatusImage(symbolName: symbolName, color: color)
            button.image = image
            button.contentTintColor = nil
        } else {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "OPC 伴侣")
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = nil
        }

        button.subviews.compactMap { $0 as? RedDotView }.forEach { $0.removeFromSuperview() }

        // 红点只表示未读提醒；浮念数量与任务状态由标题表达。
        if hasUnreadReminder {
            let dotSize: CGFloat = 6
            let frame = NSRect(
                x: button.bounds.width - dotSize - 1,
                y: button.bounds.height - dotSize - 2,
                width: dotSize,
                height: dotSize
            )
            let dot = RedDotView(frame: frame)
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            dot.layer?.cornerRadius = dotSize / 2
            dot.autoresizingMask = [.minXMargin, .minYMargin]
            button.addSubview(dot)
        }

        refreshStatusItemTitle()
    }

    private static func tintedStatusImage(symbolName: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let size = base.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private static func tintColor(for status: MenuBarStatus) -> NSColor? {
        switch status {
        case .idle: return nil
        case .focus: return .systemGreen
        case .warning: return .systemYellow
        case .overtime: return .systemRed
        case .rest: return .systemBlue
        }
    }

    func togglePanel() {
        dlog("===========================================")
        dlog("[ACTION] togglePanel called")
        dlog("[ACTION] panel exists: \(panel != nil)")
        
        if let p = panel {
            if p.isVisible {
                dlog("[ACTION] Hiding panel")
                hidePanel()
            } else {
                dlog("[ACTION] Showing panel")
                showPanel()
            }
            
            dlog("[ACTION] After toggle, isVisible: \(p.isVisible)")
        } else {
            dlog("[ERROR] panel is nil!")
        }
        dlog("===========================================")
    }

    func hidePanel() {
        dlog("[ACTION] hidePanel called")
        if let p = panel, p.isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 0.0
            }, completionHandler: {
                DispatchQueue.main.async {
                    p.orderOut(nil)
                    p.alphaValue = 1.0
                    self.state.isPanelVisible = false
                    dlog("[ACTION] Panel hidden")
                }
            })
        }
        // 关 panel 时清理可能挂起的资源：录音 + Notion 确认 continuation + 浮层
        if VoiceService.shared.isRecording {
            VoiceService.shared.stopRecording()
        }
        if NotionConfirmManager.shared.showConfirmation {
            NotionConfirmManager.shared.cancel()
        }
        // 关闭面板时同步收起"进展 ping"浮层，避免下次打开时残留出现
        state.showProgressPingPanel = false

        // H4：若 /聊聊 session 已进行 ≥3 分钟还关面板，视为用户结束清扫，避免 session 持续污染后续对话
        if let session = state.wishClearingSession, session.elapsedSeconds >= 180 {
            state.endWishClearingSession()
        }
    }

    func showPanel() {
        print("[AppDelegate] showPanel called")
        dlog("===========================================")
        dlog("[ACTION] showPanel called")

        // 先关闭 popover
        popover?.close()

        guard let p = panel else {
            dlog("[ERROR] panel is nil in showPanel!")
            return
        }
        
        dlog("[INFO] Panel before show: isVisible=\(p.isVisible), frame=\(p.frame)")
        
        // 确保 panel 不会在关闭时释放
        p.isReleasedWhenClosed = false

        // 居中到当前鼠标所在屏幕
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let screen = targetScreen {
            let visible = screen.visibleFrame
            let newX = visible.origin.x + (visible.width - p.frame.width) / 2
            let newY = visible.origin.y + (visible.height - p.frame.height) / 2
            p.setFrameOrigin(NSPoint(x: newX, y: newY))
            dlog("[ACTION] Panel centered at (\(newX), \(newY)) on screen \(screen.localizedName)")
        }
        
        // 关键顺序：先 activate app，再让 panel becomeKey，否则 macOS IME 不工作
        NSApplication.shared.activate(ignoringOtherApps: true)
        p.alphaValue = 0.0
        p.makeKeyAndOrderFront(nil)
        state.isPanelVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1.0
        }

        // 打开面板 = 用户主动回到 OPC，重置静默计时
        state.markActivity()

        // 打开面板时：每日首次检查早晨仪式（Dreaming 审核改为仪式完成后衔接 + /学习 按需召唤）
        state.checkMorningRitual()
        
        // 列出 NSApp 所有 windows
        dlog("[INFO] NSApp windows count: \(NSApplication.shared.windows.count)")
        for (i, window) in NSApplication.shared.windows.enumerated() {
            dlog("[INFO]   Window \(i): title='\(window.title)', level=\(window.level.rawValue), visible=\(window.isVisible)")
        }
        
        dlog("===========================================")
    }

    func toggleQuickCapture() {
        if let p = quickCapturePanel, p.isVisible {
            hideQuickCapture()
        } else {
            showQuickCapture()
        }
    }

    func showQuickCapture() {
        if quickCapturePanel == nil {
            quickCapturePanel = makeQuickCapturePanel()
        }
        guard let p = quickCapturePanel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let screen = targetScreen {
            let visible = screen.visibleFrame
            let x = visible.origin.x + (visible.width - p.frame.width) / 2
            let y = visible.origin.y + visible.height - p.frame.height - 80
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        p.alphaValue = 1.0
        p.makeKeyAndOrderFront(nil)
    }

    func hideQuickCapture() {
        guard let p = quickCapturePanel, p.isVisible else { return }
        // PRD-QC：捕获后快捷输入条淡出消失，不在消息流留痕。
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 0.0
        }, completionHandler: {
            // 不假设回调线程，显式派发到 main actor，避免 NSAnimationContext 线程约定变化时出错
            DispatchQueue.main.async {
                p.orderOut(nil)
                p.alphaValue = 1.0
                // 若主面板没开着，则是"闪电捕获完就走"场景 → 把 OPC 退回后台，焦点自然归还前台 app（IDE/浏览器等）
                if AppDelegate.shared?.panel?.isVisible != true {
                    NSApp.hide(nil)
                }
            }
        })
    }

    private func makeQuickCapturePanel() -> NSPanel {
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 48),
            styleMask: [.fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 520, height: 48))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let view = QuickCaptureView(
            autoStartVoice: false,
            onSubmit: { [weak self] text, inputMode in
                let source: Note.Source = (inputMode == .voice) ? .hotkeyVoice : .hotkeyText
                let saved = AppState.shared.captureNote(content: text, source: source, inputMode: inputMode)
                if saved {
                    self?.hideQuickCapture()
                }
                return saved
            },
            onCancel: { [weak self] in
                self?.hideQuickCapture()
            }
        )
        let host = NSHostingView(rootView: view.environmentObject(state))
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)

        panel.contentView = effect
        return panel
    }

    // MARK: - Quiet Field 新前门预览（v2 原型）

    func showQuietFieldPreview() {
        if quietFieldPreviewPanel == nil {
            quietFieldPreviewPanel = makeQuietFieldPreviewPanel()
        }
        guard let p = quietFieldPreviewPanel else { return }

        // 每次唤起重建内容 → 干净的折叠记一下 bar + 入场动效重放
        p.contentView = makeQuietFieldHostingView()

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let screen = targetScreen {
            let visible = screen.visibleFrame
            let x = visible.origin.x + (visible.width - p.frame.width) / 2
            // 折叠 bar 顶沿对齐主面板居中后的顶沿（方案 B 过渡：展开像从 bar 处长出，不跳位）
            let mainPanelHeight = panel?.frame.height ?? 620
            let y = visible.origin.y + (visible.height + mainPanelHeight) / 2 - p.frame.height + 16
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        // 打开主题动画门：AuroraBackground 等的 TimelineView 以 isPanelVisible 为暂停开关
        state.isPanelVisible = true
        p.alphaValue = 1.0
        p.makeKeyAndOrderFront(nil)

        // 对标旧 showPanel：重置静默计时（早晨仪式先不做，不在开门时触发）
        state.markActivity()
    }

    func hideQuietFieldPreview() {
        guard let p = quietFieldPreviewPanel, p.isVisible else { return }
        p.orderOut(nil)
        // 主面板没开着才把动画门关回去
        state.isPanelVisible = (panel?.isVisible == true)
    }

    func toggleQuietFieldPreview() {
        if let p = quietFieldPreviewPanel, p.isVisible {
            hideQuietFieldPreview()
        } else {
            showQuietFieldPreview()
        }
    }

    /// Quiet Field 收敛方案 B：折叠 bar 的「展开 / 聊聊」切到 classic 完整主面板（形态切换，非卷帘）。
    /// 清扫态由 wishClearingSession 驱动，主面板 momentStack 会自动显示清扫桌。
    func expandToMainPanel() {
        state.selectedTab = .chat   // 展开默认落在「此刻」
        isExpandingToMain = true    // 抑制 bar 的 resignKey 自动关闭，让淡出动画跑完
        showPanel()                 // 主面板在 bar 上沿位置淡入
        // 折叠 bar 同步淡出，与主面板淡入交叉 → 位置对齐使视觉上像从 bar 处展开
        if let bar = quietFieldPreviewPanel, bar.isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.animator().alphaValue = 0.0
            }, completionHandler: {
                DispatchQueue.main.async {
                    bar.orderOut(nil)
                    bar.alphaValue = 1.0
                    self.isExpandingToMain = false
                }
            })
        } else {
            isExpandingToMain = false
        }
    }

    private func makeQuietFieldPreviewPanel() -> NSPanel {
        // 复用 QuickCapturePanel 子类：已处理 canBecomeKey + 标准编辑命令转发
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear          // 折叠态只露 bar，其余透明
        panel.hasShadow = false                 // 阴影由 QuietFieldShell 自绘
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        return panel
    }

    /// 每次唤起都用新的 hosting view：保证折叠态/记一下模式/输入框状态干净、入场动效重放。
    private func makeQuietFieldHostingView() -> NSView {
        let root = QuietFieldShell()
            .environmentObject(state)
            .environment(\.theme, ThemeProvider.shared.current)   // 跟随当前主题，带上其背景动画
            .environment(\.fontStyle, FontStyleSet.from(
                FontStyleID(rawValue: state.config.fontStyleID) ?? .readable
            ))
            .preferredColorScheme(
                (ColorSchemeOverride(rawValue: state.config.colorSchemeOverride) ?? .system).resolved
            )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        return host
    }

    @MainActor func resetTimerNotifications() {
        dlog("[DIAG] resetTimerNotifications called")
        state.resetTimerFlags()
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        dlog("[EVENT] Panel will close")
        // 只隐藏面板，不释放，这样下次可以快速显示
        if let p = panel {
            p.orderOut(nil)
            state.isPanelVisible = false
            dlog("[DIAG] Panel hidden (not released)")
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow else { return }
        if closed === panel {
            dlog("[EVENT] Main panel resigned key - closing")
            hidePanel()
        } else if closed === quickCapturePanel {
            dlog("[EVENT] QuickCapture resigned key - closing")
            hideQuickCapture()
        } else if closed === quietFieldPreviewPanel {
            // 展开过渡中：bar 由 expandToMainPanel 的淡出动画收尾，不在此处抢先 orderOut（否则截断 A 过渡）
            if isExpandingToMain { return }
            dlog("[EVENT] Quiet Field preview resigned key - closing")
            hideQuietFieldPreview()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        dlog("[DIAG] applicationShouldTerminateAfterLastWindowClosed: false")
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        dlog("[DIAG] applicationWillTerminate - cleaning up resources")
        scheduledCheckTimer?.invalidate()
        scheduledCheckTimer = nil
        statusTimer?.invalidate()
        statusTimer = nil
        HotkeyHealthMonitor.shared.stop()
        CarbonHotkeyManager.shared.unregisterAll()
        if let monitor = localHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            localHotkeyMonitor = nil
        }
        if let monitor = dragHotZoneMonitor {
            NSEvent.removeMonitor(monitor)
            dragHotZoneMonitor = nil
        }
        if VoiceService.shared.isRecording {
            VoiceService.shared.stopRecording()
        }
        if NotionConfirmManager.shared.showConfirmation {
            NotionConfirmManager.shared.cancel()
        }
        cancellables.removeAll()
    }

    private func createStatusItemMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开面板", action: #selector(menuOpenPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let previewItem = NSMenuItem(title: "✨ 预览新前门 (Quiet Field)", action: #selector(menuOpenQuietFieldPreview), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let resourcesItem = NSMenuItem(title: "更多AI资源", action: #selector(menuOpenShiyeAIResources), keyEquivalent: "")
        resourcesItem.target = self
        menu.addItem(resourcesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// 按入口模式打开主入口：classic = 经典三胶囊面板；quietField = 新前门。
    private func openPrimaryEntry() {
        if state.config.entryMode == "classic" {
            showPanel()
        } else {
            showQuietFieldPreview()
        }
    }

    @objc private func menuOpenPanel() {
        dlog("[MENU] Open panel")
        openPrimaryEntry()
    }

    @objc private func menuOpenQuietFieldPreview() {
        dlog("[MENU] Open Quiet Field preview")
        popover?.close()
        showQuietFieldPreview()
    }

    @objc private func menuOpenSettings() {
        dlog("[MENU] Open settings")
        if state.config.entryMode == "classic" {
            showPanel()
            state.selectedTab = .settings
        } else {
            // 前门：唤起后点齿轮进设置
            showQuietFieldPreview()
        }
    }

    @objc private func menuOpenShiyeAIResources() {
        dlog("[MENU] Open ShiyeAI resources")
        AppBrand.openResources()
    }

    @objc private func menuQuit() {
        dlog("[MENU] Quit")
        NSApplication.shared.terminate(nil)
    }

    @objc private func handleSpaceChange() {
        dlog("[EVENT] activeSpaceDidChange - closing any visible popups")
        if panel?.isVisible == true { hidePanel() }
        if quickCapturePanel?.isVisible == true { hideQuickCapture() }
        if quietFieldPreviewPanel?.isVisible == true { hideQuietFieldPreview() }
    }
}

// MARK: - 通知点击响应

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 先完成 delegate 合约，再异步推进 UI。避免把 completionHandler 捕获进 @MainActor closure
        completionHandler()
        Task { @MainActor in
            AppDelegate.shared?.openPrimaryEntry()
            AppState.shared.selectedTab = .chat
            AppState.shared.hasUnreadReminders = false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // app 在前台时也展示横幅（macOS 默认会吞掉）
        completionHandler([.banner, .sound])
    }
}
