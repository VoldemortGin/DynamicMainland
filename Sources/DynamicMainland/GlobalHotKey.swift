import AppKit
import Carbon.HIToolbox

/// 基于 Carbon RegisterEventHotKey 的系统级热键
/// 无需辅助功能授权，且会拦截按键不再传给前台 App
final class GlobalHotKey {
    /// "DMHK"
    private static let signature: OSType = 0x444D_484B
    private static var nextId: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandlerRef: EventHandlerRef?

    private let hotKeyId: UInt32
    private var hotKeyRef: EventHotKeyRef?

    /// 注册一个系统级热键；组合键被其他 App 占用等注册失败时返回 nil。
    /// - Parameters:
    ///   - keyCode: 虚拟键码（如 kVK_ANSI_D）
    ///   - modifiers: Carbon 修饰键掩码（如 UInt32(optionKey)）
    ///   - handler: 按下时的回调，在主线程调用
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installEventHandlerIfNeeded()

        hotKeyId = Self.nextId
        Self.nextId += 1

        var ref: EventHotKeyRef?
        // 必须用 GetEventDispatcherTarget：accessory App 永不活跃，
        // 热键事件不会派发到 application target
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: hotKeyId),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("GlobalHotKey: 热键注册失败 (keyCode=%u, modifiers=%u, status=%d)",
                  keyCode, modifiers, status)
            return nil
        }
        hotKeyRef = ref
        Self.handlers[hotKeyId] = handler
    }

    deinit {
        unregister()
    }

    /// 注销热键（可重复调用）
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        Self.handlers[hotKeyId] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    GlobalHotKey.handlers[id]?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}
