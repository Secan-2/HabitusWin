import AppKit

/// 全进程共用一个事件监听。
/// 只在有功能开启且拿到辅助功能权限时启动，全部关闭时立即拆除，空闲零开销。
final class InputTap {
    static let shared = InputTap()
    static let syntheticMarker: Int64 = 0x5450494C4F54

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var swallowNextMouseUp = false

    private var mouseDownHandlers: [(CGPoint, CGEventFlags) -> Bool] = []
    private var mouseUpHandlers: [(CGPoint) -> Bool] = []
    private var keyDownHandlers: [(CGKeyCode, CGEventFlags) -> Bool] = []

    private(set) var lastError: String?

    var isRunning: Bool { tap != nil }

    private init() {}

    func addMouseDownHandler(_ handler: @escaping (CGPoint, CGEventFlags) -> Bool) {
        mouseDownHandlers.append(handler)
    }

    func addMouseUpHandler(_ handler: @escaping (CGPoint) -> Bool) {
        mouseUpHandlers.append(handler)
    }

    func addKeyDownHandler(_ handler: @escaping (CGKeyCode, CGEventFlags) -> Bool) {
        keyDownHandlers.append(handler)
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        guard Permissions.isAccessibilityTrusted else {
            lastError = "未获得辅助功能权限"
            return false
        }

        var mask: CGEventMask = 0
        mask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
        mask |= CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        mask |= CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let instance = Unmanaged<InputTap>.fromOpaque(refcon).takeUnretainedValue()
            return instance.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lastError = "事件监听创建失败"
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lastError = nil
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        swallowNextMouseUp = false
    }

    func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else {
                continue
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location

        switch type {
        case .keyDown:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            for handler in keyDownHandlers where handler(code, event.flags) {
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            for handler in mouseDownHandlers where handler(location, event.flags) {
                swallowNextMouseUp = true
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseUp:
            if swallowNextMouseUp {
                swallowNextMouseUp = false
                return nil
            }
            for handler in mouseUpHandlers where handler(location) {
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
