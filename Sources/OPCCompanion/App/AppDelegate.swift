import AppKit
import SwiftUI
import Combine
import Foundation

// 调试日志写入文件
func dlog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"

    let logDir = FileManager.default.temporaryDirectory
    let logPath = logDir.appendingPathComponent("opc_debug.log")

    // 写入文件
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath.path) {
            // 追加写入
            if let handle = try? FileHandle(forWritingTo: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            // 首次写入
            try? data.write(to: logPath)
        }
    }

    NSLog("OPC: %@", message)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!

    var panel: NSPanel?
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    var hotkeyMonitor: Any?
    var localHotkeyMonitor: Any?
    var hotkeyDownTime: Date?
    var isLongPressTriggered = false

    var state = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    private var statusTimer: Timer?
    private var scheduledCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dlog("===========================================")
        dlog("AppDelegate: applicationDidFinishLaunching START")
        dlog("===========================================")
        
        dlog("[DIAG] NSApplication.shared: \(NSApplication.shared)")
        dlog("[DIAG] NSApplication.shared.isActive: \(NSApplication.shared.isActive)")
        
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

        dlog("===========================================")
        dlog("AppDelegate: applicationDidFinishLaunching END")
        dlog("===========================================")
        
        dlog("[DIAG] FINAL - statusItem: \(statusItem != nil)")
        dlog("[DIAG] FINAL - panel: \(panel != nil)")
        dlog("[DIAG] FINAL - hotkeyMonitor: \(hotkeyMonitor != nil)")
    }

    private func setupStatusItem() {
        dlog("[DIAG] setupStatusItem: START")
        
        let systemBar = NSStatusBar.system
        dlog("[DIAG] NSStatusBar.system obtained")
        
        statusItem = systemBar.statusItem(withLength: NSStatusItem.variableLength)
        dlog("[DIAG] statusItem created")
        
        if let button = statusItem?.button {
            dlog("[DIAG] statusItem button obtained")
            button.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "OPC 伴侣")

            // 使用纯 click 而不是 sendAction
            button.target = self
            button.action = #selector(statusItemClicked)

            // 右键菜单
            button.menu = createStatusItemMenu()
            button.imagePosition = .imageLeading
            
            // 强制启用
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

        // 左键点击显示 Popover（简易面板）
        showPopover()
    }

    private func showPopover() {
        dlog("[DIAG] showPopover called")

        // 每次都创建新的 Popover 确保内容刷新
        let popoverContent = StatusBarPopoverView()
            .environmentObject(state)

        let newPopover = NSPopover()
        newPopover.contentSize = NSSize(width: 320, height: 200)
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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .utilityWindow, .closable],
            backing: .buffered,
            defer: false
        )

        dlog("[DIAG] Configuring panel properties...")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true

        // 确保不自动释放
        panel.isReleasedWhenClosed = false

        // 不需要 delegate，用户点击关闭按钮即可隐藏
        
        dlog("[DIAG] Setting panel contentView...")
        panel.contentView = hostingView
        
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
        
        dlog("[DIAG] Adding global monitor for events...")
        
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleHotkey(event: event)
        }
        
        dlog("[DIAG] Global monitor added: \(hotkeyMonitor != nil)")
        
        dlog("[DIAG] Adding local monitor for events...")
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            // Cmd+D 关闭面板 (keyCode 2 = D)
            if event.keyCode == 2 && event.modifierFlags.contains(.command) {
                dlog("[LOCAL-HOTKEY] Cmd+D detected - closing panel!")
                DispatchQueue.main.async {
                    AppDelegate.shared?.hidePanel()
                }
                return nil
            }

            self?.handleHotkey(event: event)
            
            if event.keyCode == 49 && event.modifierFlags.contains(.option) {
                return nil
            }
            return event
        }
        
        dlog("[DIAG] Local monitor added: \(localHotkeyMonitor != nil)")
        
        dlog("[DIAG] setupHotkey: END")
    }

    private func handleHotkey(event: NSEvent) {
        if event.keyCode == 49 && event.modifierFlags.contains(.option) {
            if event.type == .keyDown && !event.isARepeat {
                if hotkeyDownTime == nil {
                    hotkeyDownTime = Date()
                    isLongPressTriggered = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self, self.hotkeyDownTime != nil else { return }
                        self.isLongPressTriggered = true
                        dlog("[HOTKEY] Long press detected!")
                        if !self.panel!.isVisible {
                            self.showPanel()
                        }
                        Task { @MainActor in
                            let authorized = await VoiceService.shared.requestAuthorization()
                            if authorized && !VoiceService.shared.isRecording {
                                try? VoiceService.shared.startRecording()
                            }
                        }
                    }
                }
            } else if event.type == .keyUp {
                if let downTime = hotkeyDownTime {
                    let duration = Date().timeIntervalSince(downTime)
                    hotkeyDownTime = nil
                    
                    if duration < 0.5 && !isLongPressTriggered {
                        dlog("[HOTKEY] Short press detected!")
                        DispatchQueue.main.async {
                            AppDelegate.shared?.togglePanel()
                        }
                    } else if isLongPressTriggered {
                        dlog("[HOTKEY] Long press ended, stopping voice!")
                        Task { @MainActor in
                            if VoiceService.shared.isRecording {
                                VoiceService.shared.stopRecording()
                            }
                        }
                    }
                }
            }
        } else if event.type == .keyUp && event.keyCode == 49 {
            hotkeyDownTime = nil
            Task { @MainActor in
                if isLongPressTriggered && VoiceService.shared.isRecording {
                    VoiceService.shared.stopRecording()
                }
            }
        }
    }

    private func startScheduledTaskCheck() {
        dlog("[DIAG] startScheduledTaskCheck: START")
        
        scheduledCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            dlog("[TIMER] Scheduled task check tick")
        }
        
        dlog("[DIAG] scheduledCheckTimer created")
        dlog("[DIAG] startScheduledTaskCheck: END")
    }

    private func setupStateObservers() {
        dlog("[DIAG] setupStateObservers: START")
        dlog("[DIAG] setupStateObservers: END")
    }

    func togglePanel() {
        dlog("===========================================")
        dlog("[ACTION] togglePanel called")
        dlog("[ACTION] panel exists: \(panel != nil)")
        
        if let p = panel {
            if p.isVisible {
                dlog("[ACTION] Hiding panel")
                p.orderOut(nil)
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
            dlog("[ACTION] Panel hidden")
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
        
        // 设置位置到右上角（安全位置）
        if let screen = NSScreen.main {
            // 在菜单栏下方，从左到右排列
            let newX = screen.frame.width - p.frame.width - 50
            let newY = screen.frame.height - p.frame.height - 25
            p.setFrameOrigin(NSPoint(x: newX, y: newY))
            dlog("[ACTION] Panel at top-right: (\(newX), \(newY))")
        }
        
        // 显示面板 - 尝试多种方法
        dlog("[ACTION] Calling orderFront(nil)...")
        p.orderFront(nil)
        dlog("[ACTION] After orderFront: isVisible=\(p.isVisible)")
        
        dlog("[ACTION] Calling makeKeyAndOrderFront(nil)...")
        p.makeKeyAndOrderFront(nil)
        dlog("[ACTION] After makeKeyAndOrderFront: isVisible=\(p.isVisible)")
        
        // 强制显示
        dlog("[ACTION] Calling orderFrontRegardless...")
        p.orderFrontRegardless()
        dlog("[ACTION] After orderFrontRegardless: isVisible=\(p.isVisible)")
        
        // 尝试设置 alpha
        p.alphaValue = 1.0
        
        // 尝试设为 key window
        p.makeKey()
        
        // 激活应用
        dlog("[ACTION] Activating NSApplication...")
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // 列出 NSApp 所有 windows
        dlog("[INFO] NSApp windows count: \(NSApplication.shared.windows.count)")
        for (i, window) in NSApplication.shared.windows.enumerated() {
            dlog("[INFO]   Window \(i): title='\(window.title)', level=\(window.level.rawValue), visible=\(window.isVisible)")
        }
        
        dlog("===========================================")
    }

    @MainActor func resetTimerNotifications() {
        dlog("[DIAG] resetTimerNotifications called")
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        dlog("[EVENT] Panel will close")
        // 只隐藏面板，不释放，这样下次可以快速显示
        if let p = panel {
            p.orderOut(nil)
            dlog("[DIAG] Panel hidden (not released)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        dlog("[DIAG] applicationShouldTerminateAfterLastWindowClosed: false")
        return false
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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
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
}
