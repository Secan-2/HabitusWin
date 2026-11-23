import AppKit
import Darwin

/// 对指定的应用执行进程树强制结束。
/// Electron 应用会派生 Helper、同步服务等独立进程，只结束主进程会留下后台残留。
enum ForceQuit {
    static let defaultBundleIDs: Set<String> = ["com.zentraedi.zspaceMacApp"]

    static func terminateTree(bundleID: String) {
        let root: String? = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.bundleURL?.path
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        guard let root else {
            Log.write("force quit: app not found \(bundleID)")
            return
        }

        let prefix = root.hasSuffix("/") ? root : root + "/"
        let targets = pids(under: prefix)
        Log.write("force quit \(bundleID) pids=\(targets)")

        for pid in targets where pid != getpid() {
            errno = 0
            let result = kill(pid, SIGKILL)
            Log.write("force kill \(pid) ret=\(result) errno=\(errno)")
        }
    }

    /// 枚举可执行文件路径位于应用包内的进程，包括 Helper 与内嵌服务。
    private static func pids(under prefix: String) -> [pid_t] {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        var storage = [pid_t](repeating: 0, count: Int(count) + 64)
        count = proc_listallpids(&storage, Int32(storage.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }

        // proc_listallpids 返回的是进程个数，不是字节数
        let total = min(Int(count), storage.count)
        var result: [pid_t] = []

        for pid in storage.prefix(total) where pid > 0 {
            var path = [CChar](repeating: 0, count: Int(PATH_MAX))
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            guard length > 0 else { continue }
            let executable = String(cString: path)
            if executable.hasPrefix(prefix) {
                result.append(pid)
            }
        }
        return result
    }
}
