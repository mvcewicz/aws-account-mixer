import Carbon.HIToolbox

nonisolated enum HotKeyPreset: String, CaseIterable, Identifiable, Sendable {
    case controlOptionA, controlOptionCommandA, optionCommandK, off

    static let `default` = HotKeyPreset.controlOptionA

    var id: Self { self }

    var title: String {
        switch self {
        case .controlOptionA: "⌃⌥A"
        case .controlOptionCommandA: "⌃⌥⌘A"
        case .optionCommandK: "⌥⌘K"
        case .off: String(localized: "Off")
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .optionCommandK: UInt32(kVK_ANSI_K)
        default: UInt32(kVK_ANSI_A)
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .controlOptionA: UInt32(controlKey | optionKey)
        case .controlOptionCommandA: UInt32(controlKey | optionKey | cmdKey)
        case .optionCommandK: UInt32(optionKey | cmdKey)
        case .off: 0
        }
    }
}

/// Global shortcut via Carbon `RegisterEventHotKey` – works from any app and needs no Accessibility permission.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: () -> Void = {}

    /// `false` when another app already registered the shortcut.
    func register(_ preset: HotKeyPreset, action: @escaping () -> Void) -> Bool {
        unregister()
        guard preset != .off else { return true }
        self.action = action

        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon events for the application target arrive on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }

        let id = EventHotKeyID(signature: OSType(0x4157_4D58), id: 1) // "AWMX"
        return RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}
