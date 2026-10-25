import Darwin
import Foundation

/// Инкрементальное чтение растущего JSONL-файла с ограничениями.
///
/// - За один вызов `read()` читается не больше `maxReadBytes`.
/// - Неполная последняя строка ждёт следующего вызова, а не разбирается.
/// - Строка длиннее `maxLineBytes` в память целиком не попадает: отдаётся как
///   `.oversized` с первыми и последними `affixBytes` байтами.
/// - Усечение, замена файла (другой inode) и перезапись начала файла
///   обнаруживаются, чтение начинается заново, `Batch.didReset` = true.
public final class JSONLTailReader {
    public enum Item: Equatable, Sendable {
        case line(Data, offset: UInt64)
        case oversized(prefix: Data, suffix: Data, offset: UInt64)

        public var offset: UInt64 {
            switch self {
            case .line(_, let offset), .oversized(_, _, let offset): offset
            }
        }
    }

    public struct Batch: Sendable {
        public var items: [Item] = []
        public var didReset = false
        /// В файле есть ещё непрочитанные байты.
        public var hasMore = false
    }

    public enum ReadError: Error, Equatable {
        case missing
        case unreadable(Int32)
    }

    public let path: String
    public let maxLineBytes: Int
    public let maxReadBytes: Int
    public static let affixBytes = 4096
    static let headBytes = 64

    public private(set) var offset: UInt64 = 0
    public private(set) var fileSize: UInt64 = 0

    private var buffer = Data()
    private var lineStart: UInt64 = 0
    private var oversizedPrefix: Data?
    private var oversizedSuffix = Data()
    private var skippingToNewline = false
    private var identity: (dev: Int32, ino: UInt64)?
    private var head = Data()

    public init(path: String, maxLineBytes: Int = 1 << 20, maxReadBytes: Int = 4 << 20) {
        self.path = path
        self.maxLineBytes = maxLineBytes
        self.maxReadBytes = maxReadBytes
    }

    /// Переставить чтение. С `alignToLine` первая (обрезанная) строка пропускается.
    public func seek(to newOffset: UInt64, alignToLine: Bool) {
        resetBuffers()
        offset = newOffset
        lineStart = newOffset
        guard alignToLine, newOffset > 0 else { return }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var byte: UInt8 = 0
        // Если предыдущий байт — перевод строки, мы уже на начале строки.
        skippingToNewline = !(pread(fd, &byte, 1, off_t(newOffset - 1)) == 1 && byte == 0x0A)
    }

    public func read() throws(ReadError) -> Batch {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw errno == ENOENT ? .missing : .unreadable(errno) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw .unreadable(errno) }

        var batch = Batch()
        let size = UInt64(max(0, info.st_size))
        let current = (dev: info.st_dev, ino: info.st_ino)
        if let identity, identity.dev != current.dev || identity.ino != current.ino {
            restart(); batch.didReset = true
        } else if size < offset {
            restart(); batch.didReset = true
        } else if !head.isEmpty, readBytes(fd, at: 0, count: head.count) != head {
            restart(); batch.didReset = true
        }
        identity = current
        fileSize = size
        if head.count < Self.headBytes, size > UInt64(head.count) {
            head = readBytes(fd, at: 0, count: Int(min(size, UInt64(Self.headBytes))))
        }

        guard size > offset else { return batch }
        let count = Int(min(size - offset, UInt64(maxReadBytes)))
        let chunk = readBytes(fd, at: offset, count: count)
        consume(chunk, startingAt: offset, into: &batch.items)
        offset += UInt64(chunk.count)
        batch.hasMore = offset < size
        return batch
    }

    private func consume(_ chunk: Data, startingAt base: UInt64, into items: inout [Item]) {
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            let segment = chunk[start..<newline]
            if skippingToNewline {
                skippingToNewline = false
            } else if let prefix = oversizedPrefix {
                appendSuffix(segment)
                items.append(.oversized(prefix: prefix, suffix: oversizedSuffix, offset: lineStart))
                oversizedPrefix = nil
                oversizedSuffix = Data()
            } else {
                buffer.append(segment)
                if buffer.last == 0x0D { buffer.removeLast() }
                if buffer.count > maxLineBytes {
                    items.append(.oversized(
                        prefix: Data(buffer.prefix(Self.affixBytes)),
                        suffix: Data(buffer.suffix(Self.affixBytes)),
                        offset: lineStart))
                } else if !buffer.isEmpty {
                    items.append(.line(buffer, offset: lineStart))
                }
                buffer = Data()
            }
            start = chunk.index(after: newline)
            lineStart = base + UInt64(start - chunk.startIndex)
        }
        let rest = chunk[start...]
        if skippingToNewline { return }
        if oversizedPrefix != nil {
            appendSuffix(rest)
        } else {
            buffer.append(rest)
            if buffer.count > maxLineBytes {
                oversizedPrefix = Data(buffer.prefix(Self.affixBytes))
                oversizedSuffix = Data(buffer.suffix(Self.affixBytes))
                buffer = Data()
            }
        }
    }

    private func appendSuffix(_ bytes: Data) {
        oversizedSuffix.append(bytes)
        if oversizedSuffix.count > Self.affixBytes {
            oversizedSuffix = Data(oversizedSuffix.suffix(Self.affixBytes))
        }
    }

    private func restart() {
        resetBuffers()
        offset = 0
        lineStart = 0
        head = Data()
        identity = nil
    }

    private func resetBuffers() {
        buffer = Data()
        oversizedPrefix = nil
        oversizedSuffix = Data()
        skippingToNewline = false
    }

    private func readBytes(_ fd: Int32, at position: UInt64, count: Int) -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { raw -> Int in
            var total = 0
            while total < count {
                let n = pread(fd, raw.baseAddress! + total, count - total, off_t(position) + off_t(total))
                if n > 0 { total += n } else if n < 0 && errno == EINTR { continue } else { break }
            }
            return total
        }
        if read < count { data.removeSubrange(read...) }
        return data
    }
}

extension JSONLTailReader {
    /// Первая строка файла без чтения остального. Используется для заголовка
    /// rollout-а Codex, когда остальной файл читается с хвоста.
    static func firstLine(path: String, limit: Int = 1 << 20) -> Item? {
        let reader = JSONLTailReader(path: path, maxLineBytes: limit, maxReadBytes: 256 << 10)
        var read = 0
        while read <= limit + (256 << 10) {
            guard let batch = try? reader.read() else { return nil }
            if let first = batch.items.first { return first }
            guard batch.hasMore else { return nil }
            read += 256 << 10
        }
        return nil
    }
}
