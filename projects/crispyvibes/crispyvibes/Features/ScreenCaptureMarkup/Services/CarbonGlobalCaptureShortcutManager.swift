import AppKit
import Carbon
import Foundation

/// Carbon `RegisterEventHotKey` adapter. It observes only explicitly registered chords.
@MainActor
final class CarbonGlobalCaptureShortcutManager: GlobalCaptureShortcutManaging {
    private struct Registration {
        let reference: EventHotKeyRef
        let shortcut: GlobalCaptureShortcut
    }

    private static let signature: OSType = 0x43525350 // "CRSP"

    private let commandHandler: (GlobalCaptureShortcutCommand) -> Void
    private var registrations: [GlobalCaptureShortcutCommand: Registration] = [:]
    private var registrationStates: [GlobalCaptureShortcutCommand: GlobalCaptureShortcutRegistration] = [:]
    private var eventHandler: EventHandlerRef?
    private var commandByID: [UInt32: GlobalCaptureShortcutCommand] = [:]
    var onRegistrationChanged: (() -> Void)?

    init(commandHandler: @escaping (GlobalCaptureShortcutCommand) -> Void) {
        self.commandHandler = commandHandler
    }

    func registration(for command: GlobalCaptureShortcutCommand) -> GlobalCaptureShortcutRegistration {
        registrationStates[command] ?? .disabled
    }

    func rebind(
        _ command: GlobalCaptureShortcutCommand,
        to shortcut: GlobalCaptureShortcut?
    ) -> GlobalCaptureShortcutRegistration {
        unregister(command)
        guard let shortcut else {
            registrationStates[command] = .disabled
            notifyChange()
            return .disabled
        }
        installEventHandlerIfNeeded()
        let identifier = commandIdentifier(command)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        let result: GlobalCaptureShortcutRegistration
        if status == noErr, let reference {
            registrations[command] = Registration(reference: reference, shortcut: shortcut)
            commandByID[identifier] = command
            result = .registered(shortcut)
        } else if status == eventHotKeyExistsErr {
            result = .conflict(shortcut)
        } else {
            result = .failed(shortcut)
        }
        registrationStates[command] = result
        notifyChange()
        return result
    }

    func unregister(_ command: GlobalCaptureShortcutCommand) {
        if let registration = registrations.removeValue(forKey: command) {
            UnregisterEventHotKey(registration.reference)
        }
        commandByID.removeValue(forKey: commandIdentifier(command))
        registrationStates[command] = .disabled
    }

    func shutdown() {
        for command in GlobalCaptureShortcutCommand.allCases {
            unregister(command)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        onRegistrationChanged = nil
        notifyChange()
    }

    static func shortcut(from binding: AppShortcutBinding?) -> GlobalCaptureShortcut? {
        guard let binding else { return nil }
        var carbonModifiers: UInt32 = 0
        let flags = binding.modifierFlags
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        return GlobalCaptureShortcut(keyCode: UInt32(binding.keyCode), modifiers: carbonModifiers)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<CarbonGlobalCaptureShortcutManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return MainActor.assumeIsolated {
                    manager.handleHotKey(id: hotKeyID)
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func handleHotKey(id: EventHotKeyID) -> OSStatus {
        guard id.signature == Self.signature,
              let command = commandByID[id.id] else {
            return OSStatus(eventNotHandledErr)
        }
        commandHandler(command)
        return noErr
    }

    private func commandIdentifier(_ command: GlobalCaptureShortcutCommand) -> UInt32 {
        UInt32((GlobalCaptureShortcutCommand.allCases.firstIndex(of: command) ?? 0) + 1)
    }

    private func notifyChange() {
        onRegistrationChanged?()
    }
}
