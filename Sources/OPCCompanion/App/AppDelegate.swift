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

final class YellowBadgeView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        guard !text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let nsText = text as NSString
        let textSize = nsText.size(withAttributes: attrs)
        let origin = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2
        )
        nsText.draw(at: origin, withAttributes: attrs)
    }
}

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!

    var panel: NSPanel?
    var quickCapturePanel: NSPanel?
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    var hotkeyMonitor: Any?
    var localHotkeyMonitor: Any?
    var hotkeyDownTime: Date?
    var isLongPressTriggered = false
    private var lastSpaceKeyDownAt: Date = .distantPast
    private var lastQuickCaptureAt: Date = .distantPast

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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        dlog("[DIAG] Configuring panel properties...")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        // 不加入所有 Space：用户切换到其他 Space 时面板应消失而不是闪现
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = AppCornerRadius.panel
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]

        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)

        dlog("[DIAG] Setting panel contentView...")
        panel.contentView = effectView
        
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
        let optionMod = UInt32(optionKey)

        // Option + Space (keyCode 49)：短按 toggle 面板，长按 ≥500ms 语音模式
        CarbonHotkeyManager.shared.register(
            keyCode: 49, modifiers: optionMod,
            onPress: { [weak self] in self?.handleOptSpacePress() },
            onRelease: { [weak self] in self?.handleOptSpaceRelease() }
        )

        // Option + ` (keyCode 50)：切换快捷输入条
        CarbonHotkeyManager.shared.register(
            keyCode: 50, modifiers: optionMod,
            onPress: { [weak self] in self?.handleOptBacktickPress() }
        )
        dlog("[DIAG] Carbon hotkeys registered")

        // Local monitor 保留：Esc 关面板 / Cmd+D 关面板（只在 app 内生效）
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 2 && event.modifierFlags.contains(.command) {
                dlog("[LOCAL-HOTKEY] Cmd+D detected - closing panel!")
                DispatchQueue.main.async { AppDelegate.shared?.hidePanel() }
                return nil
            }
            if event.keyCode == 53 {
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

    // MARK: - Carbon hotkey handlers

    private func handleOptSpacePress() {
        let now = Date()
        if now.timeIntervalSince(lastSpaceKeyDownAt) < 0.2 { return }
        lastSpaceKeyDownAt = now
        hotkeyDownTime = now
        isLongPressTriggered = false

        // 500ms 之后还在按 → 长按进入语音（用 Task.sleep 替代 asyncAfter 避免 Swift 6 isolation check）
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self = self, self.hotkeyDownTime != nil else { return }
            self.isLongPressTriggered = true
            dlog("[HOTKEY] Long press detected!")
            if let p = self.panel, !p.isVisible { self.showPanel() }
            let authorized = await VoiceService.shared.requestAuthorization()
            if authorized && !VoiceService.shared.isRecording {
                try? VoiceService.shared.startRecording()
            }
        }
    }

    private func handleOptSpaceRelease() {
        guard let downTime = hotkeyDownTime else { return }
        let duration = Date().timeIntervalSince(downTime)
        hotkeyDownTime = nil

        if duration < 0.5 && !isLongPressTriggered {
            dlog("[HOTKEY] Short press - toggle panel")
            togglePanel()
        } else if isLongPressTriggered {
            dlog("[HOTKEY] Long press ended - stop voice")
            Task { @MainActor in
                if VoiceService.shared.isRecording {
                    VoiceService.shared.stopRecording()
                }
            }
        }
    }

    private func handleOptBacktickPress() {
        let now = Date()
        if now.timeIntervalSince(lastQuickCaptureAt) < 0.3 { return }
        lastQuickCaptureAt = now
        dlog("[HOTKEY] Option+` - toggle quick capture")
        toggleQuickCapture()
    }

    // 旧的 NSEvent global monitor 版本 handleHotkey 已被 Carbon 版替换

    private func startScheduledTaskCheck() {
        dlog("[DIAG] startScheduledTaskCheck: START")

        requestNotificationAuthorization()
        state.checkScheduledTasks()

        scheduledCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                AppState.shared.checkScheduledTasks()
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
        let incompletePub = state.$tasks.map { tasks in
            tasks.contains { $0.status == .pending || $0.status == .inProgress }
        }
        state.$menuBarStatus
            .combineLatest(state.$hasUnreadReminders, incompletePub)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status, unread, hasIncomplete in
                self?.updateStatusItemAppearance(status: status, hasUnread: unread || hasIncomplete)
            }
            .store(in: &cancellables)

        updateStatusItemAppearance(
            status: state.menuBarStatus,
            hasUnread: state.hasUnreadReminders || state.hasIncompleteTasks
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
        guard let active = state.activeTask,
              active.status == .inProgress,
              let remaining = active.remainingSeconds else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            return
        }

        let truncated: String = active.title.count > 8
            ? String(active.title.prefix(7)) + "…"
            : active.title
        let mm = remaining / 60
        let ss = remaining % 60
        let text = " \(truncated) \(String(format: "%02d:%02d", mm, ss))"

        let color: NSColor
        let weight: NSFont.Weight
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

        let attributed = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: weight)
        ])
        button.attributedTitle = attributed
    }

    private func updateStatusItemAppearance(status: MenuBarStatus, hasUnread: Bool) {
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

        // 清除旧角标（兼容历史 YellowBadgeView 残留）
        button.subviews.compactMap { $0 as? RedDotView }.forEach { $0.removeFromSuperview() }
        button.subviews.compactMap { $0 as? YellowBadgeView }.forEach { $0.removeFromSuperview() }

        // 红点 — 有待办任务或未读提醒时显示
        if hasUnread {
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
                p.orderOut(nil)
                state.isPanelVisible = false
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
            p.orderOut(nil)
            state.isPanelVisible = false
            dlog("[ACTION] Panel hidden")
        }
        // 关 panel 时清理可能挂起的资源：录音 + Notion 确认 continuation
        if VoiceService.shared.isRecording {
            VoiceService.shared.stopRecording()
        }
        if NotionConfirmManager.shared.showConfirmation {
            NotionConfirmManager.shared.cancel()
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
        p.alphaValue = 1.0
        p.makeKeyAndOrderFront(nil)
        state.isPanelVisible = true
        
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
        quickCapturePanel?.orderOut(nil)
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
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let view = QuickCaptureView(
            autoStartVoice: true,
            onSubmit: { [weak self] text, inputMode in
                let source: Note.Source = (inputMode == .voice) ? .hotkeyVoice : .hotkeyText
                AppState.shared.captureNote(content: text, source: source, inputMode: inputMode)
                self?.hideQuickCapture()
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
        CarbonHotkeyManager.shared.unregisterAll()
        if let monitor = localHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            localHotkeyMonitor = nil
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

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let debugItem = NSMenuItem(title: "调试：循环图标颜色", action: #selector(menuDebugCycleStatus), keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)

        let debugDotItem = NSMenuItem(title: "调试：切换红点", action: #selector(menuDebugToggleDot), keyEquivalent: "")
        debugDotItem.target = self
        menu.addItem(debugDotItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func menuDebugCycleStatus() {
        // 末尾停在 focus（绿色），避免循环回 idle 导致"看起来没变色"
        let sequence: [MenuBarStatus] = [.idle, .focus, .warning, .overtime, .rest, .focus]
        Task { @MainActor in
            for status in sequence {
                state.menuBarStatus = status
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @objc private func menuDebugToggleDot() {
        state.hasUnreadReminders.toggle()
    }

    @objc private func menuOpenPanel() {
        dlog("[MENU] Open panel")
        showPanel()
    }

    @objc private func menuOpenSettings() {
        dlog("[MENU] Open settings")
        showPanel()
        state.selectedTab = .settings
    }

    @objc private func menuQuit() {
        dlog("[MENU] Quit")
        NSApplication.shared.terminate(nil)
    }

    @objc private func handleSpaceChange() {
        dlog("[EVENT] activeSpaceDidChange - closing any visible popups")
        if panel?.isVisible == true { hidePanel() }
        if quickCapturePanel?.isVisible == true { hideQuickCapture() }
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
            AppDelegate.shared?.showPanel()
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
