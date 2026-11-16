import Foundation
import Combine

enum WindowButtonAction: String, CaseIterable, Identifiable {
    case none
    case closeWindow
    case quitApp
    case minimizeWindow
    case hideApp
    case zoomWindow
    case toggleFullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不响应"
        case .closeWindow: return "关闭窗口"
        case .quitApp: return "退出应用"
        case .minimizeWindow: return "最小化窗口"
        case .hideApp: return "隐藏应用"
        case .zoomWindow: return "缩放窗口"
        case .toggleFullScreen: return "切换全屏"
        }
    }
}

enum DockClickAction: String, CaseIterable, Identifiable {
    case none
    case minimizeFrontWindow
    case minimizeAllWindows
    case hideApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "保持系统默认"
        case .minimizeFrontWindow: return "最小化当前窗口"
        case .minimizeAllWindows: return "最小化全部窗口"
        case .hideApp: return "隐藏应用"
        }
    }
}

enum SettingsKey {
    static let schemaVersion = "settings.schema"
    static let trafficLightEnabled = "tl.enabled"
    static let redAction = "tl.red"
    static let yellowAction = "tl.yellow"
    static let greenAction = "tl.green"
    static let hideWhenNoAccessibility = "tl.requireAX"

    static let cutEnabled = "cut.enabled"
    static let cutSound = "cut.sound"
    static let cutVolume = "cut.volume"

    static let dockEnabled = "dock.enabled"
    static let dockAction = "dock.action"
    static let dockPrecise = "dock.precise"
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// 首次安装时为真，用于决定是否自动打开设置窗口。
    let wasFirstRun: Bool

    let changes = PassthroughSubject<Void, Never>()

    private let defaults = UserDefaults.standard

    /// 每次调整默认行为或写入迁移逻辑时递增。
    private static let currentSchema = 3

    @Published var trafficLightEnabled: Bool {
        didSet { persist(trafficLightEnabled, SettingsKey.trafficLightEnabled); changes.send() }
    }

    @Published var redAction: WindowButtonAction {
        didSet { persist(redAction.rawValue, SettingsKey.redAction); changes.send() }
    }

    @Published var yellowAction: WindowButtonAction {
        didSet { persist(yellowAction.rawValue, SettingsKey.yellowAction); changes.send() }
    }

    @Published var greenAction: WindowButtonAction {
        didSet { persist(greenAction.rawValue, SettingsKey.greenAction); changes.send() }
    }

    @Published var cutEnabled: Bool {
        didSet { persist(cutEnabled, SettingsKey.cutEnabled); changes.send() }
    }

    @Published var cutSound: String {
        didSet { persist(cutSound, SettingsKey.cutSound); changes.send() }
    }

    @Published var cutVolume: Double {
        didSet { persist(cutVolume, SettingsKey.cutVolume); changes.send() }
    }

    @Published var dockEnabled: Bool {
        didSet { persist(dockEnabled, SettingsKey.dockEnabled); changes.send() }
    }

    @Published var dockAction: DockClickAction {
        didSet { persist(dockAction.rawValue, SettingsKey.dockAction); changes.send() }
    }

    @Published var dockPrecise: Bool {
        didSet { persist(dockPrecise, SettingsKey.dockPrecise); changes.send() }
    }

    /// 红色按钮设为「退出应用」时，访达等系统常驻应用保持原生行为。
    private init() {
        Self.migrateLegacyPreferencesIfNeeded()

        let storedSchema = Self.readInt(SettingsKey.schemaVersion, default: 0)
        wasFirstRun = storedSchema == 0

        // v2：首次安装与升级都回到系统原样，三个功能全部默认关闭，由用户逐个打开。
        if storedSchema < 2 {
            UserDefaults.standard.set(false, forKey: SettingsKey.trafficLightEnabled)
            UserDefaults.standard.set(false, forKey: SettingsKey.cutEnabled)
            UserDefaults.standard.set(false, forKey: SettingsKey.dockEnabled)
        }

        // v3：默认音效换成随包的切纸声，用户自己挑过的保持不动。
        if storedSchema < 3 {
            let stored = UserDefaults.standard.string(forKey: SettingsKey.cutSound) ?? "Pop"
            if stored == "Pop" {
                UserDefaults.standard.set(SoundPlayer.bundledName, forKey: SettingsKey.cutSound)
            }
        }

        if storedSchema < Self.currentSchema {
            UserDefaults.standard.set(Self.currentSchema, forKey: SettingsKey.schemaVersion)
        }

        trafficLightEnabled = Self.readBool(SettingsKey.trafficLightEnabled, default: false)
        redAction = WindowButtonAction(rawValue: Self.readString(SettingsKey.redAction, default: "closeWindow")) ?? .closeWindow
        yellowAction = WindowButtonAction(rawValue: Self.readString(SettingsKey.yellowAction, default: "minimizeWindow")) ?? .minimizeWindow
        greenAction = WindowButtonAction(rawValue: Self.readString(SettingsKey.greenAction, default: "toggleFullScreen")) ?? .toggleFullScreen
        cutEnabled = Self.readBool(SettingsKey.cutEnabled, default: false)
        cutSound = Self.readString(SettingsKey.cutSound, default: SoundPlayer.bundledName)
        cutVolume = Self.readDouble(SettingsKey.cutVolume, default: 0.6)
        dockEnabled = Self.readBool(SettingsKey.dockEnabled, default: false)
        dockAction = DockClickAction(rawValue: Self.readString(SettingsKey.dockAction, default: "minimizeFrontWindow")) ?? .minimizeFrontWindow
        dockPrecise = Self.readBool(SettingsKey.dockPrecise, default: true)
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    func action(for kind: LightKind) -> WindowButtonAction {
        switch kind {
        case .close: return redAction
        case .minimize: return yellowAction
        case .zoom: return greenAction
        }
    }

    private static func readBool(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    private static func readString(_ key: String, default fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    private static func readDouble(_ key: String, default fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    private static func readInt(_ key: String, default fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }

    /// 从旧名字 TrafficPilot 迁移偏好设置，改名不至于让用户重新配一遍。
    private static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKey.schemaVersion) == nil else { return }
        guard let legacy = UserDefaults(suiteName: "com.local.TrafficPilot") else { return }

        let keys = [
            SettingsKey.schemaVersion,
            SettingsKey.trafficLightEnabled,
            SettingsKey.redAction,
            SettingsKey.yellowAction,
            SettingsKey.greenAction,
            SettingsKey.cutEnabled,
            SettingsKey.cutSound,
            SettingsKey.cutVolume,
            SettingsKey.dockEnabled,
            SettingsKey.dockAction,
            SettingsKey.dockPrecise
        ]

        for key in keys {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
