import Foundation

/// The bridge and saved history contain Russian operation labels. Translate at
/// display time so changing the app language also updates existing sessions.
/// Unknown tool names and MCP server names must remain verbatim.
func localizedAgentOperation(_ operation: String) -> String {
    let key: String
    switch operation {
    case "Запуск команды": key = "Run Command"
    case "Выполнение кода": key = "Run Code"
    case "Чтение файла": key = "Read File"
    case "Запись файла": key = "Write File"
    case "Правка файла": key = "Edit File"
    case "Поиск по файлам": key = "Search Files"
    case "Загрузка страницы": key = "Fetch Page"
    case "Поиск в интернете": key = "Search Web"
    case "Субагент": key = "Subagent"
    case "План задач": key = "Task Plan"
    case "Вопрос пользователю": key = "Ask User"
    case "Сжатие контекста": key = "Compact Context"
    case "Ход прерван": key = "Turn Interrupted"
    case "Работа с изображением": key = "Image Operation"
    default: return operation
    }
    return localized(key)
}
