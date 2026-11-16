import AppKit
import ApplicationServices

enum AX {
    static func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attr(element, name) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let value = attr(element, name) else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attr(element, name) as? String
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = attr(element, kAXPositionAttribute),
              let sizeValue = attr(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    static func setFrame(_ element: AXUIElement, _ rect: CGRect) -> Bool {
        var point = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return true
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ name: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse)) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// 命中测试。坐标使用主屏左上角为原点的屏幕坐标，与 CGEvent.location 一致。
    static func element(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide,
                                               Float(point.x),
                                               Float(point.y),
                                               &element) == .success else {
            return nil
        }
        return element
    }

    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }
}

enum Geometry {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    static func axRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    static func screen(containingAX rect: CGRect) -> NSScreen? {
        let cocoa = cocoaRect(fromAX: rect)
        return NSScreen.screens.first { $0.frame.intersects(cocoa) } ?? NSScreen.main
    }
}
