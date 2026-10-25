import AgentBridgeCore
import Darwin
import Foundation
import SandyMobileCore

// sandy-agent — мост между Sandy и Claude Code / Codex. Контракт и
// ограничения: docs/agent-bridge.md.
//
// stdout монитора — только события JSONL. Диагностика — только stderr.

let version = "1"
let arguments = Array(CommandLine.arguments.dropFirst())

func diagnose(_ message: String) {
    FileHandle.standardError.write(Data(("sandy-agent: " + message + "\n").utf8))
}

func usage() -> Never {
    diagnose("""
    usage:
      sandy-agent monitor [--claude] [--codex] [--codex-home PATH] [--spool-dir PATH]
                          [--replay-window SECONDS] [--poll-interval SECONDS]
      sandy-agent claude-hook [--spool-dir PATH]
      sandy-agent install-claude-hooks [--settings PATH] [--hook-executable PATH] [--dry-run]
      sandy-agent uninstall-claude-hooks [--settings PATH] [--dry-run]
    """)
    exit(64)
}

struct Options {
    var flags: Set<String> = []
    var values: [String: String] = [:]

    init(_ args: ArraySlice<String>, flags allowedFlags: Set<String>, values allowedValues: Set<String>) {
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            if allowedFlags.contains(arg) {
                flags.insert(arg)
            } else if allowedValues.contains(arg), let value = iterator.next() {
                values[arg] = value
            } else {
                diagnose("неизвестный аргумент: \(arg)")
                usage()
            }
        }
    }

    func path(_ key: String) -> URL? {
        guard let value = values[key] else { return nil }
        guard value.hasPrefix("/") else { diagnose("\(key) ждёт абсолютный путь"); usage() }
        return URL(fileURLWithPath: value)
    }

    func seconds(_ key: String, default fallback: Double) -> Double {
        guard let value = values[key] else { return fallback }
        guard let number = Double(value), number > 0, number.isFinite else { diagnose("\(key): не число"); usage() }
        return number
    }
}

// MARK: claude-hook

/// Никогда не блокирует Claude и ничего не печатает в stdout: для
/// UserPromptSubmit и SessionStart stdout стал бы контекстом модели, для
/// PermissionRequest — решением. Код выхода всегда 0.
func runClaudeHook(_ options: Options) -> Never {
    // Claude всегда закрывает stdin; на случай, если нет, — не висеть.
    signal(SIGALRM) { _ in _exit(0) }
    alarm(3)
    signal(SIGPIPE, SIG_IGN)
    let limit = 32 << 20
    var input = Data()
    while true {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: 1 << 16), !chunk.isEmpty else { break }
        // Сверх предела дочитываем вхолостую, чтобы Claude не получил EPIPE.
        if input.count < limit { input.append(chunk.prefix(limit - input.count)) }
    }
    let debug = ProcessInfo.processInfo.environment["SANDY_AGENT_DEBUG"] == "1"
    guard let record = ClaudeHookRecord.make(
        payload: input, now: Date(), owner: ProcessInspector.hookOwner()) else {
        if debug { diagnose("payload не распознан") }
        exit(0)
    }
    let spool = ClaudeSpool(directory: options.path("--spool-dir") ?? ClaudeSpool.defaultDirectory())
    do {
        try spool.append(record)
    } catch {
        if debug { diagnose("не записано: \(error)") }
    }
    exit(0)
}

// MARK: monitor

final class Output {
    func write(_ event: AgentEvent) {
        var line = event.jsonLine()
        line.append(0x0A)
        let ok = line.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(STDOUT_FILENO, raw.baseAddress! + offset, raw.count - offset)
                if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { return false }
            }
            return true
        }
        // Sandy закрыл канал — наблюдать больше не для кого.
        if !ok { exit(0) }
    }
}

func runMonitor(_ options: Options) -> Never {
    let claude = options.flags.contains("--claude")
    let codex = options.flags.contains("--codex")
    guard claude || codex else { diagnose("monitor: нужен --claude и/или --codex"); usage() }
    signal(SIGPIPE, SIG_IGN)

    let interval = options.seconds("--poll-interval", default: 1)
    let window = options.seconds("--replay-window", default: 12 * 3600)
    let output = Output()
    let pipeline = EventPipeline(output: output.write)
    let log: (String) -> Void = { diagnose($0) }

    var codexMonitor: CodexMonitor?
    if codex {
        var codexOptions = CodexMonitor.Options()
        codexOptions.replayWindow = window
        codexMonitor = CodexMonitor(
            codexHome: options.path("--codex-home") ?? CodexMonitor.defaultHome(),
            options: codexOptions, log: log)
    }
    var claudeMonitor: ClaudeMonitor?
    if claude {
        var claudeOptions = ClaudeMonitor.Options()
        claudeOptions.replayWindow = window
        claudeMonitor = ClaudeMonitor(
            spool: ClaudeSpool(directory: options.path("--spool-dir") ?? ClaudeSpool.defaultDirectory()),
            options: claudeOptions, log: log)
    }

    // Один поток, kqueue: сигналы останова и таймер опроса в одном ожидании.
    let queue = kqueue()
    guard queue >= 0 else { diagnose("kqueue: \(errno)"); exit(70) }
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig, SIG_IGN)
        var change = kevent(ident: UInt(sig), filter: Int16(EVFILT_SIGNAL), flags: UInt16(EV_ADD),
                            fflags: 0, data: 0, udata: nil)
        _ = kevent(queue, &change, 1, nil, 0, nil)
    }

    func poll() {
        codexMonitor?.poll(into: pipeline)
        claudeMonitor?.poll(into: pipeline)
    }
    poll()
    pipeline.flushReplay()

    let parent = getppid()
    var timeout = timespec(tv_sec: Int(interval), tv_nsec: Int((interval - floor(interval)) * 1e9))
    while true {
        var event = kevent()
        let n = kevent(queue, nil, 0, &event, 1, &timeout)
        if n > 0, event.filter == Int16(EVFILT_SIGNAL) { break }
        // Sandy упал, не остановив нас: не оставаться сиротой.
        if getppid() != parent { break }
        poll()
    }
    exit(0)
}

// MARK: hooks install

func currentExecutable() -> String {
    let raw = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    return URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
}

func runInstall(_ options: Options, install: Bool) -> Never {
    let settings = options.path("--settings") ?? ClaudeSettingsInstaller.defaultSettingsURL()
    let dryRun = options.flags.contains("--dry-run")
    do {
        let outcome: ClaudeSettingsInstaller.Outcome
        if install {
            let executable = options.path("--hook-executable")?.path ?? currentExecutable()
            if !executable.contains(".app/Contents/Helpers/") {
                diagnose("предупреждение: хук будет ссылаться на \(executable), а не на хелпер внутри Sandy.app")
            }
            outcome = try ClaudeSettingsInstaller.install(settingsURL: settings, executable: executable, dryRun: dryRun)
        } else {
            outcome = try ClaudeSettingsInstaller.uninstall(settingsURL: settings, dryRun: dryRun)
        }
        let verb = dryRun ? "будет изменён" : "изменён"
        if outcome.changed {
            diagnose("\(settings.path) \(verb); снято прежних записей Sandy: \(outcome.removedHandlers)")
            if let backup = outcome.backup { diagnose("резервная копия: \(backup.path)") }
        } else {
            diagnose("\(settings.path) не требует изменений")
        }
        exit(0)
    } catch {
        diagnose(error.description)
        exit(1)
    }
}

// MARK: entry

guard let command = arguments.first else { usage() }
let rest = arguments.dropFirst()
switch command {
case "monitor":
    runMonitor(Options(rest, flags: ["--claude", "--codex"],
                       values: ["--codex-home", "--spool-dir", "--replay-window", "--poll-interval"]))
case "claude-hook":
    // Незнакомые аргументы не роняют хук: Claude не должен видеть ошибок.
    var hookOptions = Options([], flags: [], values: [])
    if let index = rest.firstIndex(of: "--spool-dir"), rest.index(after: index) < rest.endIndex,
       rest[rest.index(after: index)].hasPrefix("/") {
        hookOptions.values["--spool-dir"] = rest[rest.index(after: index)]
    }
    runClaudeHook(hookOptions)
case "mobile-approval":
    runMobileApproval()
    exit(0)
case "install-mobile-approvals", "uninstall-mobile-approvals":
    let options = Options(rest, flags: [], values: ["--settings", "--hook-executable"])
    do {
        _ = try ClaudeSettingsInstaller.mobileApprovals(
            settingsURL: options.path("--settings") ?? ClaudeSettingsInstaller.defaultSettingsURL(),
            executable: options.path("--hook-executable")?.path ?? currentExecutable(),
            install: command == "install-mobile-approvals")
        exit(0)
    } catch { diagnose("could not update mobile approvals"); exit(1) }
case "install-claude-hooks":
    runInstall(Options(rest, flags: ["--dry-run"], values: ["--settings", "--hook-executable"]), install: true)
case "uninstall-claude-hooks":
    runInstall(Options(rest, flags: ["--dry-run"], values: ["--settings"]), install: false)
case "--version", "version":
    print("sandy-agent \(version)")
    exit(0)
default:
    usage()
}
