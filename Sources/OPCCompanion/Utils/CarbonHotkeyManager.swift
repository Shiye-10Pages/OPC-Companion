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
public final class CarbonHotkeyManager: @unchecked Sendable {
    public static let shared = CarbonHotkeyManager()

    private struct Slot {
        let id: UInt32
        let hotKeyRef: EventHotKeyRef
        let onPress: () -> Void
        let onRelease: () -> Void
    }

    private let lock = NSLock()
    private var slots: [UInt32: Slot] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

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
        lock.lock()
        defer { lock.unlock() }

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
        guard status == noErr, let ref = ref else { return nil }
        slots[id] = Slot(id: id, hotKeyRef: ref, onPress: onPress, onRelease: onRelease)
        return id
    }

    public func unregister(id: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slots.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(slot.hotKeyRef)
    }

    public func unregisterAll() {
        lock.lock()
        defer { lock.unlock() }
        for (_, slot) in slots {
            UnregisterEventHotKey(slot.hotKeyRef)
        }
        slots.removeAll()
    }

    // MARK: - Internal

    private static let signature: OSType = OSType(bitPattern: 0x4F504331)  // 'OPC1'

    private func installEventHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event = event, let userData = userData else {
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
                guard err == noErr else { return OSStatus(eventNotHandledErr) }

                let kind = GetEventKind(event)
                let manager = Unmanaged<CarbonHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.lock.lock()
                    defer { manager.lock.unlock() }
                    guard let slot = manager.slots[hotKeyID.id] else { return }
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
    }
}
