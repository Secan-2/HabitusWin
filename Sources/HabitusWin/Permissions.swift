import AppKit
import ApplicationServices
import Security

enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 真正发一次 AX 调用，用于区分「未授权」与「已授权但 AX 不可用」。
    /// kAXErrorAPIDisabled 表示当前进程没有辅助功能权限。
    static func probeAXError() -> AXError {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        return AXUIElementCopyElementAtPosition(systemWide, 10, 10, &element)
    }

    static func requestAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSApp.activate(ignoringOtherApps: true)
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// 清理本应用在 TCC 里的旧记录。历史构建的残留条目会让勾选无法生效。
    @discardableResult
    static func resetAccessibility() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static var bundlePath: String {
        Bundle.main.bundlePath
    }

    /// 被 Gatekeeper 重定位到随机只读路径时，授权永远无法持久化。
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    static var isInApplicationsFolder: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// 用于诊断：ad-hoc 签名没有 Team ID，TCC 只能按 cdhash 记忆授权，
    /// 每次重新构建都会让旧授权失效。
    static func signatureSummary() -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "未知" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return "未知"
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,
                                            SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let dict = information as? [String: Any] else {
            return "未知"
        }
        let flags = dict[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        if flags & 0x2 != 0 { return "ad-hoc 自签名" }
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String {
            return "Developer ID \(team)"
        }
        return "已签名"
    }

    struct Diagnostics {
        var trusted: Bool
        var axError: AXError
        var path: String
        var translocated: Bool
        var inApplications: Bool

        var axErrorText: String {
            switch axError {
            case .success: return "正常"
            case .apiDisabled: return "AX 接口被系统禁用，即未授权"
            case .cannotComplete: return "调用超时，目标进程无响应"
            default: return "错误码 \(axError.rawValue)"
            }
        }
    }

    static func diagnostics() -> Diagnostics {
        Diagnostics(trusted: isAccessibilityTrusted,
                    axError: probeAXError(),
                    path: bundlePath,
                    translocated: isTranslocated,
                    inApplications: isInApplicationsFolder)
    }
}

extension Notification.Name {
    static let permissionStateChanged = Notification.Name("HabitusWin.permissionStateChanged")
}
