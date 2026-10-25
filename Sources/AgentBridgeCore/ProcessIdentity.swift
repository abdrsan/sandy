import Darwin
import Foundation

/// Процесс, опознанный по pid и времени запуска: pid переиспользуются, пара — нет.
public struct ProcessIdentity: Codable, Equatable, Sendable {
    public var pid: Int32
    /// Время запуска, секунды от 1970 с микросекундами.
    public var startTime: Double

    public init(pid: Int32, startTime: Double) {
        self.pid = pid
        self.startTime = startTime
    }
}

public enum ProcessInspector {
    struct Info {
        var parent: Int32
        var name: String
        var startTime: Double
    }

    static func info(_ pid: Int32) -> Info? {
        guard pid > 0 else { return nil }
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &process, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: process.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let start = process.kp_proc.p_un.__p_starttime
        return Info(
            parent: process.kp_eproc.e_ppid,
            name: name,
            startTime: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    public static func identity(of pid: Int32) -> ProcessIdentity? {
        info(pid).map { ProcessIdentity(pid: pid, startTime: $0.startTime) }
    }

    public static func isAlive(_ identity: ProcessIdentity) -> Bool {
        guard let info = info(identity.pid) else { return false }
        return abs(info.startTime - identity.startTime) < 0.001
    }

    /// Процесс Claude Code, запустивший хук. Хук в форме строки идёт через
    /// `sh -c`, поэтому промежуточные оболочки пропускаются.
    public static func hookOwner(startingAt parent: Int32 = getppid()) -> ProcessIdentity? {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env"]
        var pid = parent
        for _ in 0..<4 {
            guard pid > 1, let info = info(pid) else { return nil }
            if !shells.contains(info.name) {
                return ProcessIdentity(pid: pid, startTime: info.startTime)
            }
            pid = info.parent
        }
        return nil
    }
}
