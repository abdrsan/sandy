import Carbon
import Testing
@testable import Sandy

@MainActor
private final class FakeShortcutRegistration: ShortcutRegistering {
    var succeeds = true
    var registered: [PanelShortcut] = []
    var action: (@MainActor () -> Void)?
    func register(_ shortcut: PanelShortcut, action: @escaping @MainActor () -> Void) -> Bool {
        registered.append(shortcut)
        self.action = succeeds ? action : nil
        return succeeds
    }
    func unregister() { action = nil }
}

@MainActor
struct GlobalShortcutTests {
    @Test func disabledShortcutDoesNotRegisterAndStoppingReleasesCallback() {
        let registration = FakeShortcutRegistration()
        var presses = 0
        var savedEnabled = false
        let store = GlobalShortcut(enabled: false, shortcut: .controlOptionSpace,
                                   registration: registration, persist: { enabled, _ in savedEnabled = enabled })
        store.start { presses += 1 }
        #expect(registration.registered.isEmpty)
        store.setEnabled(true)
        #expect(savedEnabled)
        registration.action?()
        #expect(presses == 1)
        store.setEnabled(false)
        #expect(registration.action == nil)
        store.setEnabled(true)
        store.stop()
        #expect(registration.action == nil)
    }

    @Test func conflictingShortcutCanBeReplacedAndSaved() {
        let registration = FakeShortcutRegistration()
        registration.succeeds = false
        var saved: PanelShortcut?
        let store = GlobalShortcut(enabled: true, shortcut: .controlOptionSpace,
                                   registration: registration, persist: { _, shortcut in saved = shortcut })
        store.start {}
        #expect(store.registrationFailed)
        registration.succeeds = true
        store.select(.commandShiftSpace)
        #expect(!store.registrationFailed)
        #expect(saved == .commandShiftSpace)
        #expect(registration.registered == [.controlOptionSpace, .commandShiftSpace])
        #expect(registration.action != nil)
    }

    @Test func defaultShortcutUsesPhysicalSpaceAndControlOption() {
        #expect(PanelShortcut.controlOptionSpace.keyCode == UInt32(kVK_Space))
        #expect(PanelShortcut.controlOptionSpace.modifiers == UInt32(controlKey | optionKey))
        #expect(PanelShortcut.controlOptionS.keyCode == UInt32(kVK_ANSI_S))
    }
}
