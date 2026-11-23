import Foundation

/// 极简本地日志，只记录退出与点击判定，用于排查「点了没反应」这类问题。
/// 单文件上限 256KB，超出就重来，不做上传。
enum Log {
    private static let queue = DispatchQueue(label: "com.local.HabitusWin.log")
    private static let limit = 256 * 1024
    private static let path = NSHomeDirectory() + "/Library/Logs/HabitusWin.log"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static var fileURL: URL { URL(fileURLWithPath: path) }

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            let fm = FileManager.default
            if let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int, size > limit {
                try? fm.removeItem(atPath: path)
            }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
}
