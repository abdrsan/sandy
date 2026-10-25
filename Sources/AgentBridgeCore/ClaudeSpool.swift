import Darwin
import Foundation

/// Почтовый ящик между хуком Claude Code и монитором.
///
/// Хук только дописывает одну строку в файл своей сессии и сразу выходит:
/// ни сокета, ни ожидания, поэтому выключенный Sandy Claude не тормозит.
/// Монитор читает эти файлы тем же `JSONLTailReader`, что и журналы Codex,
/// а после своего перезапуска поднимает из них текущее состояние.
public struct ClaudeSpool: Sendable {
    public let directory: URL
    /// При превышении файл сессии заменяется одной новой строкой.
    public var maxFileBytes: Int = 1 << 20

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["SANDY_AGENT_SPOOL_DIR"], custom.hasPrefix("/") {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sandy/AgentBridge/claude", isDirectory: true)
    }

    public func fileURL(for sessionID: String) -> URL {
        directory.appendingPathComponent("\(sessionID).jsonl")
    }

    public enum AppendError: Error { case directory(Int32), open(Int32), write(Int32) }

    public func append(_ record: ClaudeHookRecord) throws(AppendError) {
        try ensureDirectory()
        var line = record.jsonLine()
        line.append(0x0A)
        let path = fileURL(for: record.sessionID).path
        // O_NOFOLLOW: подменённый симлинком файл сессии не уведёт запись.
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw .open(errno) }
        var info = stat()
        if fstat(fd, &info) == 0, info.st_size + off_t(line.count) > off_t(maxFileBytes) {
            close(fd)
            try replace(path: path, with: line)
            return
        }
        defer { close(fd) }
        // Одна запись write(): параллельные хуки одной сессии не перемешают строки.
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw .write(errno) }
    }

    private func replace(path: String, with line: Data) throws(AppendError) {
        let temporary = path + ".\(getpid()).tmp"
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw .open(errno) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
        guard written == line.count, rename(temporary, path) == 0 else {
            unlink(temporary)
            throw .write(errno)
        }
    }

    private func ensureDirectory() throws(AppendError) {
        var info = stat()
        if lstat(directory.path, &info) == 0 {
            // Каталог должен быть настоящим и нашим.
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { throw .directory(EPERM) }
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            throw .directory(errno)
        }
    }
}
