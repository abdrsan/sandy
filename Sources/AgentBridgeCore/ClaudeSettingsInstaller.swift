import Foundation

/// Установка и удаление хуков Sandy в настройках Claude Code
/// (`~/.claude/settings.json` или `$CLAUDE_CONFIG_DIR/settings.json`).
///
/// - Чужие хуки и прочие настройки не трогаются.
/// - Перед любой записью рядом сохраняется резервная копия.
/// - Свои записи узнаются по команде: путь к `sandy-agent` и `claude-hook`.
///   Отдельной метки нет, потому что Claude Code проверяет схему настроек.
/// - Нечитаемый файл не перезаписывается.
public enum ClaudeSettingsInstaller {
    public struct Hook: Sendable {
        public var event: String
        public var matcher: String?
        public var timeout: Int?
    }

    /// Хук — короткая запись в файл, поэтому синхронный: так сохраняется
    /// порядок событий. Таймаут — страховка на случай зависшего диска.
    /// SessionEnd без собственного таймаута: иначе Claude Code поднимает
    /// общий бюджет ожидания при выходе.
    public static let hooks: [Hook] = [
        Hook(event: "SessionStart", matcher: nil, timeout: 5),
        Hook(event: "UserPromptSubmit", matcher: nil, timeout: 5),
        Hook(event: "PreToolUse", matcher: "*", timeout: 5),
        Hook(event: "PostToolUse", matcher: "*", timeout: 5),
        Hook(event: "PostToolUseFailure", matcher: "*", timeout: 5),
        Hook(event: "PermissionRequest", matcher: "*", timeout: 5),
        Hook(event: "Notification", matcher: nil, timeout: 5),
        Hook(event: "PreCompact", matcher: nil, timeout: 5),
        Hook(event: "Stop", matcher: nil, timeout: 5),
        Hook(event: "StopFailure", matcher: nil, timeout: 5),
        Hook(event: "SessionEnd", matcher: nil, timeout: nil)
    ]

    public enum InstallError: Error, CustomStringConvertible {
        case unreadable(String)
        case notAnObject
        case hooksNotAnObject
        case write(String)

        public var description: String {
            switch self {
            case .unreadable(let reason): "настройки не читаются как JSON (\(reason)); файл не изменён"
            case .notAnObject: "настройки — не JSON-объект; файл не изменён"
            case .hooksNotAnObject: "поле hooks — не объект; файл не изменён"
            case .write(let reason): "не удалось записать настройки: \(reason)"
            }
        }
    }

    public struct Outcome: Sendable {
        public var changed: Bool
        public var backup: URL?
        public var removedHandlers: Int
    }

    public static func defaultSettingsURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let dir = environment["CLAUDE_CONFIG_DIR"], dir.hasPrefix("/") {
            return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("settings.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Команда в форме для `sh -c`: путь в одинарных кавычках. Если Sandy
    /// удалили, не сняв хуки, команда молча завершается с 0 — иначе Claude
    /// показывал бы ошибку хука на каждом событии.
    public static func command(executable: String) -> String {
        let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "[ ! -x \(quoted) ] || \(quoted) claude-hook"
    }

    /// Узнаёт и эту форму, и прежнюю без проверки `-x`.
    public static func isSandyCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(" claude-hook") else { return false }
        var program = String(trimmed.dropLast(" claude-hook".count))
        if let split = program.range(of: "] || ", options: .backwards) {
            program = String(program[split.upperBound...])
        }
        let unquoted = program.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            .replacingOccurrences(of: "'\\''", with: "'")
        return (unquoted as NSString).lastPathComponent == "sandy-agent"
    }

    // MARK: Чистые преобразования

    public static func installing(into settings: JSONObject, command: String) throws(InstallError) -> JSONObject {
        var (result, _) = try removing(from: settings)
        var hooksObject = result.object("hooks") ?? [:]
        for hook in hooks {
            var handler: JSONObject = ["type": "command", "command": command]
            if let timeout = hook.timeout { handler["timeout"] = timeout }
            var group: JSONObject = ["hooks": [handler]]
            if let matcher = hook.matcher { group["matcher"] = matcher }
            var groups = hooksObject.array(hook.event) ?? []
            groups.append(group)
            hooksObject[hook.event] = groups
        }
        result["hooks"] = hooksObject
        return result
    }

    public static func removing(from settings: JSONObject) throws(InstallError) -> (JSONObject, Int) {
        guard let raw = settings["hooks"] else { return (settings, 0) }
        guard var hooksObject = raw as? JSONObject else { throw .hooksNotAnObject }
        var removed = 0
        for (event, value) in hooksObject {
            guard let groups = value as? [Any] else { continue }
            var kept: [Any] = []
            var touched = false
            for entry in groups {
                guard var group = entry as? JSONObject, let handlers = group["hooks"] as? [Any] else {
                    kept.append(entry); continue
                }
                let filtered = handlers.filter { handler in
                    guard let object = handler as? JSONObject, object.string("type") == "command",
                          let command = object.string("command"), isSandyCommand(command) else { return true }
                    return false
                }
                guard filtered.count != handlers.count else { kept.append(entry); continue }
                removed += handlers.count - filtered.count
                touched = true
                // Группа, опустевшая из-за нас, исчезает; с чужими хуками — остаётся.
                if !filtered.isEmpty {
                    group["hooks"] = filtered
                    kept.append(group)
                }
            }
            guard touched else { continue }
            if kept.isEmpty { hooksObject.removeValue(forKey: event) } else { hooksObject[event] = kept }
        }
        var result = settings
        if removed > 0 {
            if hooksObject.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooksObject }
        }
        return (result, removed)
    }

    // MARK: Файл

    public static func install(settingsURL: URL, executable: String, dryRun: Bool = false,
                               now: Date = Date()) throws(InstallError) -> Outcome {
        let (current, existed, file) = try read(settingsURL)
        let updated = try installing(into: current, command: command(executable: executable))
        let (_, removed) = try removing(from: current)
        return try commit(updated, over: current, existed: existed, file: file, removed: removed,
                          dryRun: dryRun, now: now)
    }

    public static func uninstall(settingsURL: URL, dryRun: Bool = false,
                                 now: Date = Date()) throws(InstallError) -> Outcome {
        let (current, existed, file) = try read(settingsURL)
        let (updated, removed) = try removing(from: current)
        guard removed > 0 else { return Outcome(changed: false, backup: nil, removedHandlers: 0) }
        return try commit(updated, over: current, existed: existed, file: file, removed: removed,
                          dryRun: dryRun, now: now)
    }

    public static func mobileApprovals(settingsURL: URL, executable: String, install: Bool) throws(InstallError) -> Outcome {
        let (current, existed, file) = try read(settingsURL)
        var updated = current
        guard current["hooks"] == nil || current["hooks"] is JSONObject else { throw .hooksNotAnObject }
        var hooksObject = current.object("hooks") ?? [:]
        var removed = 0
        var groups: [Any] = []
        for raw in hooksObject.array("PermissionRequest") ?? [] {
            guard var group = raw as? JSONObject, let handlers = group["hooks"] as? [Any] else { groups.append(raw); continue }
            let kept = handlers.filter { entry in
                guard let obj = entry as? JSONObject, let command = obj.string("command"), command.hasSuffix(" mobile-approval") else { return true }
                return !isSandyCommand(String(command.dropLast(" mobile-approval".count)) + " claude-hook")
            }
            removed += handlers.count - kept.count
            if !kept.isEmpty { group["hooks"] = kept; groups.append(group) }
        }
        if install {
            let command = String(command(executable: executable).dropLast(" claude-hook".count)) + " mobile-approval"
            groups.append(["matcher":"*", "hooks":[["type":"command", "command":command,"timeout":100]]])
        }
        if groups.isEmpty { hooksObject.removeValue(forKey:"PermissionRequest") } else { hooksObject["PermissionRequest"] = groups }
        updated["hooks"] = hooksObject
        return try commit(updated,over:current,existed:existed,file:file,removed:removed,dryRun:false,now:Date())
    }

    private static func read(_ url: URL) throws(InstallError) -> (JSONObject, Bool, URL) {
        // Настройки часто — симлинк в репозиторий dotfiles: пишем в цель.
        let file = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: file.path) else { return ([:], false, file) }
        let data: Data
        do { data = try Data(contentsOf: file) } catch { throw .unreadable(error.localizedDescription) }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return ([:], true, file) }
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: data) } catch { throw .unreadable("JSON") }
        guard let object = parsed as? JSONObject else { throw .notAnObject }
        return (object, true, file)
    }

    private static func commit(_ updated: JSONObject, over current: JSONObject, existed: Bool, file: URL,
                               removed: Int, dryRun: Bool, now: Date) throws(InstallError) -> Outcome {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard var data = try? JSONSerialization.data(withJSONObject: updated, options: options) else {
            throw .write("сериализация")
        }
        data.append(0x0A)
        if existed, let old = try? JSONSerialization.data(withJSONObject: current, options: options),
           old + [0x0A] == data {
            return Outcome(changed: false, backup: nil, removedHandlers: removed)
        }
        if dryRun { return Outcome(changed: true, backup: nil, removedHandlers: removed) }

        let manager = FileManager.default
        var backup: URL?
        var permissions: Int = 0o600
        do {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            if existed {
                permissions = (try manager.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) ?? 0o600
                let stamp = now.formatted(Date.ISO8601FormatStyle(timeZone: .gmt)
                    .year().month().day().dateSeparator(.omitted)
                    .time(includingFractionalSeconds: false).timeSeparator(.omitted))
                var target = file.deletingLastPathComponent()
                    .appendingPathComponent("\(file.lastPathComponent).sandy-backup-\(stamp)")
                var suffix = 1
                while manager.fileExists(atPath: target.path) {
                    suffix += 1
                    target = file.deletingLastPathComponent()
                        .appendingPathComponent("\(file.lastPathComponent).sandy-backup-\(stamp)-\(suffix)")
                }
                try manager.copyItem(at: file, to: target)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                backup = target
            }
            try data.write(to: file, options: .atomic)
            try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        } catch {
            throw .write(error.localizedDescription)
        }
        return Outcome(changed: true, backup: backup, removedHandlers: removed)
    }
}
