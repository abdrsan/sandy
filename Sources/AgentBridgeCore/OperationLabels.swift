import Foundation

/// Название действия по имени инструмента. Аргументы инструмента сюда не
/// попадают никогда — только имя, и то после очистки.
public enum OperationLabels {
    public static let runCommand = "Запуск команды"
    public static let runCode = "Выполнение кода"
    public static let readFile = "Чтение файла"
    public static let writeFile = "Запись файла"
    public static let editFile = "Правка файла"
    public static let search = "Поиск по файлам"
    public static let webFetch = "Загрузка страницы"
    public static let webSearch = "Поиск в интернете"
    public static let subagent = "Субагент"
    public static let plan = "План задач"
    public static let question = "Вопрос пользователю"
    public static let compaction = "Сжатие контекста"
    public static let interrupted = "Ход прерван"
    public static let image = "Работа с изображением"

    /// Имя инструмента без всего, что могло бы оказаться данными.
    public static func sanitizedToolName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.:")
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter(allowed.contains)).prefix(80))
        return cleaned.isEmpty ? nil : cleaned
    }

    public static func claude(tool raw: String?) -> String? {
        guard let tool = sanitizedToolName(raw) else { return nil }
        if let mcp = mcpLabel(tool) { return mcp }
        switch tool {
        case "Bash", "PowerShell", "BashOutput", "KillShell", "KillBash": return runCommand
        case "Read", "NotebookRead": return readFile
        case "Write": return writeFile
        case "Edit", "MultiEdit", "NotebookEdit": return editFile
        case "Glob", "Grep", "LS", "ToolSearch": return search
        case "WebFetch": return webFetch
        case "WebSearch": return webSearch
        case "Task", "Agent", "SendMessage", "TaskOutput": return subagent
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "ExitPlanMode", "EnterPlanMode": return plan
        case "AskUserQuestion": return question
        default: return tool
        }
    }

    public static func codex(tool raw: String?) -> String? {
        guard let tool = sanitizedToolName(raw) else { return nil }
        if let mcp = mcpLabel(tool) { return mcp }
        switch tool {
        case "shell", "shell_command", "exec_command", "local_shell", "container.exec", "write_stdin":
            return runCommand
        case "exec", "js", "node_repl", "python": return runCode
        case "apply_patch": return editFile
        case "web_search", "web_search_call": return webSearch
        case "view_image", "image_generation": return image
        case "update_plan": return plan
        case "spawn_agent", "send_message", "wait", "wait_agent", "list_agents",
             "interrupt_agent", "followup_task", "close_agent", "resume_agent":
            return subagent
        case "request_user_input", "request_user_input_async": return question
        case "tool_search": return search
        default: return tool
        }
    }

    /// `mcp__github__create_issue` → `MCP: github`.
    private static func mcpLabel(_ tool: String) -> String? {
        guard tool.hasPrefix("mcp__") else { return nil }
        let server = tool.dropFirst(5).components(separatedBy: "__").first ?? ""
        return server.isEmpty ? "MCP" : "MCP: \(server)"
    }
}
