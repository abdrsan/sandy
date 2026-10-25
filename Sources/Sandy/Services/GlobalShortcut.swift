import AppKit
import Carbon
import Combine

enum PanelShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
    case controlOptionSpace, controlShiftSpace, commandShiftSpace, controlOptionS
    var id: String { rawValue }
    var title: String {
        switch self {
        case .controlOptionSpace: "⌃⌥" + localized("Space")
        case .controlShiftSpace: "⌃⇧" + localized("Space")
        case .commandShiftSpace: "⌘⇧" + localized("Space")
        case .controlOptionS: "⌃⌥S"
        }
    }
    var keyCode: UInt32 { UInt32(self == .controlOptionS ? kVK_ANSI_S : kVK_Space) }
    var modifiers: UInt32 {
        switch self {
        case .controlOptionSpace, .controlOptionS: UInt32(controlKey | optionKey)
        case .controlShiftSpace: UInt32(controlKey | shiftKey)
        case .commandShiftSpace: UInt32(cmdKey | shiftKey)
        }
    }
}

@MainActor
protocol ShortcutRegistering: AnyObject {
    func register(_ shortcut: PanelShortcut, action: @escaping @MainActor () -> Void) -> Bool
    func unregister()
}

/// Carbon hot keys work across applications without Accessibility permission.
/// Physical key codes keep the shortcut working with Cyrillic and Chinese input.
@MainActor
final class CarbonShortcutRegistration: ShortcutRegistering {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private static let signature: OSType = 0x53414E44 // SAND

    func register(_ shortcut: PanelShortcut, action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x53414E44, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            // Application event handlers run on the application's main loop.
            MainActor.assumeIsolated {
                Unmanaged<CarbonShortcutRegistration>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { unregister(); return false }
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                        GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else { unregister(); return false }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }
}

@MainActor
final class GlobalShortcut: ObservableObject {
    static let shared = GlobalShortcut(
        enabled: ConfigStore.shared.panelShortcutEnabled,
        shortcut: ConfigStore.shared.panelShortcut,
        registration: CarbonShortcutRegistration(),
        persist: { enabled, shortcut in
            ConfigStore.shared.panelShortcutEnabled = enabled
            ConfigStore.shared.panelShortcut = shortcut
        }
    )

    @Published private(set) var enabled: Bool
    @Published private(set) var shortcut: PanelShortcut
    @Published private(set) var registrationFailed = false
    private let registration: any ShortcutRegistering
    private let persist: (Bool, PanelShortcut) -> Void
    private var action: (@MainActor () -> Void)?

    init(enabled: Bool, shortcut: PanelShortcut, registration: any ShortcutRegistering,
         persist: @escaping (Bool, PanelShortcut) -> Void) {
        self.enabled = enabled
        self.shortcut = shortcut
        self.registration = registration
        self.persist = persist
    }

    func start(action: @escaping @MainActor () -> Void) {
        self.action = action
        update()
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        persist(enabled, shortcut)
        update()
    }

    func select(_ shortcut: PanelShortcut) {
        self.shortcut = shortcut
        persist(enabled, shortcut)
        update()
    }

    func stop() {
        registration.unregister()
        action = nil
        registrationFailed = false
    }

    private func update() {
        registration.unregister()
        registrationFailed = false
        guard enabled, let action else { return }
        registrationFailed = !registration.register(shortcut, action: action)
    }
}
