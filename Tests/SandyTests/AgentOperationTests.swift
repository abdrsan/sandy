import Foundation
import Testing
@testable import Sandy

struct AgentOperationTests {
    @Test func bridgeLabelsFollowAppLanguageWithoutChangingStoredOperations() {
        #expect(localizedAgentOperation("Запуск команды") == localized("Run Command"))
        #expect(localizedAgentOperation("Чтение файла") == localized("Read File"))
        #expect(localizedAgentOperation("Сжатие контекста") == localized("Compact Context"))
        #expect(localizedAgentOperation("Ход прерван") == localized("Turn Interrupted"))
    }

    @Test func toolAndMCPNamesStayVerbatim() {
        #expect(localizedAgentOperation("MCP: github") == "MCP: github")
        #expect(localizedAgentOperation("custom_tool") == "custom_tool")
    }
}
