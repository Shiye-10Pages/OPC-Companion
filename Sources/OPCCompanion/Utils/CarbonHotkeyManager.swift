import AppKit
import Carbon.HIToolbox

/// 用 Carbon `RegisterEventHotKey` 注册全局热键。不需要辅助功能权限（不同于
/// `NSEvent.addGlobalMonitorForEvents`）。
///
/// 支持 `onPress` / `onRelease` 两种回调，调用方可以据此识别长按：
/// ```
/// let press = Date()
/// register(... onPress: { press = Date() }, onRelease: {
///     let duration = Date().timeIntervalSince(press)
///     // duration < 0.5 → 短按；否则长按
/// })
/// ```
///
/// 诊断（HOTKEY-DIAG）：
/// - register 入口 + RegisterEventHotKey OSStatus
/// - installEventHandler 入口 + InstallEventHandler OSStatus
/// - Carbon C callback 入口（确认事件是否真的被派发过来）
/// - slot 查找成功/失败
/// - onPress / onRelease 调用前后
public final class CarbonHotkeyManager: @unchecked Sendable {
    public static let shared = CarbonHotkeyManager()

    private struct Slot {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let hotKeyRef: EventHotKeyRef
        let onPress: () -> Void
        let onRelease: () -> Void
    }

    private var slots: [UInt32: Slot] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private(set) var handlerInstalled: Bool = false
    private(set) var handlerInstallStatus: OSStatus = noErr

    /// callback 是否真的被 Carbon 派发过（用于"5 秒内没回调就告警/启用 fallback"判断）
    private(set) var callbackEverFired: Bool = false

    private init() {
        installEventHandler()
    }

    // MARK: - Public

    /// 注册一个全局热键。返回内部分配的 id（用于反注册）。失败返回 nil。
    @discardableResult
    public func register(
        keyCode: UInt32,
        modifiers: UInt32,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void = {}
    ) -> UInt32? {
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            // -9878 (eventHotKeyExistsErr) 通常意味着该组合已被其他 app/系统占用
            OPCLogger.shared.log(
                .error,
                "hotkey",
                "RegisterEventHotKey FAILED id=\(id) keyCode=\(keyCode) modifiers=0x\(String(modifiers, radix: 16)) status=\(status) — 该热键可能已被系统或其他 App 占用（如系统输入法切换抢占 Option+Space），请到「系统设置 → 键盘 → 键盘快捷键」检查冲突"
            )
            return nil
        }
        guard let ref = ref else {
            OPCLogger.shared.log(
                .error,
                "hotkey",
                "RegisterEventHotKey returned noErr but ref is nil — Carbon internal error id=\(id)"
            )
            return nil
        }
        slots[id] = Slot(
            id: id,
            keyCode: keyCode,
            modifiers: modifiers,
            hotKeyRef: ref,
            onPress: onPress,
            onRelease: onRelease
        )
        diag("[register] OK id=\(id) keyCode=\(keyCode) slots.count=\(slots.count)")
        return id
    }

    public func unregister(id: UInt32) {
        guard let slot = slots.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(slot.hotKeyRef)
    }

    public func unregisterAll() {
        for (_, slot) in slots {
            UnregisterEventHotKey(slot.hotKeyRef)
        }
        slots.removeAll()
    }

    /// 调试快照：当前已注册的热键 id / keyCode / modifiers 列表
    public func currentRegistrationsSnapshot() -> String {
        let entries = slots.values.map { "id=\($0.id) keyCode=\($0.keyCode) mod=0x\(String($0.modifiers, radix: 16))" }
        return "[snapshot] handlerInstalled=\(handlerInstalled) handlerInstallStatus=\(handlerInstallStatus) callbackEverFired=\(callbackEverFired) secureInput=\(Self.isSecureInputEnabled()) count=\(slots.count) entries=[\(entries.joined(separator: "; "))]"
    }

    /// 实时探测 macOS Secure Event Input 状态。
    /// 某个 App（终端 sudo/SSH、密码管理器、网页密码字段等）启用 Secure Input 时，
    /// 第三方全局热键会被屏蔽，直到该进程失焦才自动解除。这与"几分钟后突然好用"现象吻合。
    public static func isSecureInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    // MARK: - Internal

    private static let signature: OSType = OSType(bitPattern: 0x4F504331)  // 'OPC1'

    private func installEventHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                // 注意：这是 Carbon C callback，可能在主线程之外。OPCLogger 内部 NSLock 保护，可安全调用。
                guard let event = event, let userData = userData else {
                    OPCLogger.shared.log(.warn, "hotkey", "[CB] event or userData is nil")
                    return OSStatus(eventNotHandledErr)
                }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else {
                    OPCLogger.shared.log(.warn, "hotkey", "[CB] GetEventParameter failed err=\(err)")
                    return OSStatus(eventNotHandledErr)
                }

                let kind = GetEventKind(event)
                let manager = Unmanaged<CarbonHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let wasFiredBefore = manager.callbackEverFired
                manager.callbackEverFired = true
                OPCLogger.shared.log(.info, "hotkey", "[CB] entry id=\(hotKeyID.id) kind=\(kind == UInt32(kEventHotKeyPressed) ? "PRESSED" : (kind == UInt32(kEventHotKeyReleased) ? "RELEASED" : "kind=\(kind)"))")

                if !wasFiredBefore {
                    // 首次 fire → 通知 HotkeyHealthMonitor 清掉警告 banner
                    DispatchQueue.main.async {
                        HotkeyHealthMonitor.shared.notifyCallbackFired()
                    }
                }

                DispatchQueue.main.async {
                    guard let slot = manager.slots[hotKeyID.id] else {
                        OPCLogger.shared.log(.warn, "hotkey", "[CB] slot NOT FOUND id=\(hotKeyID.id) slots=\(manager.slots.keys.sorted())")
                        return
                    }
                    if kind == UInt32(kEventHotKeyPressed) {
                        slot.onPress()
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        slot.onRelease()
                    }
                }
                return noErr
            },
            2,
            &types,
            selfPtr,
            &eventHandler
        )
        handlerInstallStatus = status
        if status == noErr {
            handlerInstalled = true
        } else {
            handlerInstalled = false
            OPCLogger.shared.log(
                .error,
                "hotkey",
                "InstallEventHandler FAILED status=\(status) — Carbon 事件处理器未装载，所有热键将不会触发回调"
            )
        }
    }

    private func diag(_ msg: String) {
        OPCLogger.shared.log(.info, "hotkey", "[HOTKEY-DIAG] \(msg)")
    }
}
