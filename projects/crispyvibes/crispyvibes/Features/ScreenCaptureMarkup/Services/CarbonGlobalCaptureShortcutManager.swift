import AppKit
import Carbon
import Foundation
/// Injectable boundary around the Carbon hot-key APIs used by F062.
@MainActor
struct CarbonGlobalShortcutAPI {
    let installEventHandler: (
        inout EventTypeSpec,
        EventHandlerUPP?,
        UnsafeMutableRawPointer,
        inout EventHandlerRef?
    ) -> OSStatus
    let registerEventHotKey: (
        GlobalCaptureShortcut,
        EventHotKeyID,
        OptionBits,
        inout EventHotKeyRef?
    ) -> OSStatus
    let unregisterEventHotKey: (EventHotKeyRef) -> OSStatus
    let removeEventHandler: (EventHandlerRef) -> OSStatus
    let readEventHotKeyID: (EventRef, inout EventHotKeyID) -> OSStatus
    static let live = CarbonGlobalShortcutAPI(
        installEventHandler: { eventType, callback, userData, handler in
            InstallEventHandler(
                GetApplicationEventTarget(),
                callback,
                1,
                &eventType,
                userData,
                &handler
            )
        },
        registerEventHotKey: { shortcut, identifier, options, reference in
            RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                identifier,
                GetApplicationEventTarget(),
                options,
                &reference
            )
        },
        unregisterEventHotKey: { reference in
            UnregisterEventHotKey(reference)
        },
        removeEventHandler: { handler in
            RemoveEventHandler(handler)
        },
        readEventHotKeyID: { event, identifier in
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
        }
    )
}
/// Carbon `RegisterEventHotKey` adapter. It observes only explicitly registered chords.
@MainActor
final class CarbonGlobalCaptureShortcutManager: GlobalCaptureShortcutManaging {
    typealias DiagnosticHandler = (_ operation: String, _ status: String, _ count: UInt64) -> Void
    private final class CallbackContext {
        weak var manager: CarbonGlobalCaptureShortcutManager?
        init(manager: CarbonGlobalCaptureShortcutManager) {
            self.manager = manager
        }
    }
    private struct Registration {
        let reference: EventHotKeyRef
        let shortcut: GlobalCaptureShortcut
    }
    private static let signature: OSType = 0x43525350 // "CRSP"
    static let exclusiveRegistrationOptions = OptionBits(kEventHotKeyExclusive)
    private let api: CarbonGlobalShortcutAPI
    private let statusHandler: (String, OSStatus) -> Void
    private let diagnosticHandler: DiagnosticHandler
    private let commandHandler: (GlobalCaptureShortcutCommand) -> Void
    private var registrations: [GlobalCaptureShortcutCommand: Registration] = [:]
    private var registrationStates: [GlobalCaptureShortcutCommand: GlobalCaptureShortcutRegistration] = [:]
    private var eventHandler: EventHandlerRef?
    private var eventHandlerContext: UnsafeMutableRawPointer?
    private var partialEventHandler: EventHandlerRef?
    private var partialEventHandlerContext: UnsafeMutableRawPointer?
    private var commandByID: [UInt32: GlobalCaptureShortcutCommand] = [:]
    private var callbackCount: UInt64 = 0
    private var dispatchCount: UInt64 = 0
    private var eventHandlerOwnershipValidForTesting = true
    private(set) var lastInstallEventHandlerStatus: OSStatus?
    private(set) var lastUnregisterEventHotKeyStatus: OSStatus?
    private(set) var lastRemoveEventHandlerStatus: OSStatus?
    var onRegistrationChanged: (() -> Void)?
    init(
        api: CarbonGlobalShortcutAPI,
        statusHandler: @escaping (String, OSStatus) -> Void = { _, _ in },
        diagnosticHandler: @escaping DiagnosticHandler = { _, _, _ in },
        commandHandler: @escaping (GlobalCaptureShortcutCommand) -> Void
    ) {
        self.api = api
        self.statusHandler = statusHandler
        self.diagnosticHandler = diagnosticHandler
        self.commandHandler = commandHandler
    }
    convenience init(
        statusHandler: @escaping (String, OSStatus) -> Void,
        diagnosticHandler: @escaping DiagnosticHandler = { _, _, _ in },
        commandHandler: @escaping (GlobalCaptureShortcutCommand) -> Void
    ) {
        self.init(
            api: .live,
            statusHandler: statusHandler,
            diagnosticHandler: diagnosticHandler,
            commandHandler: commandHandler
        )
    }
    convenience init(commandHandler: @escaping (GlobalCaptureShortcutCommand) -> Void) {
        self.init(api: .live, commandHandler: commandHandler)
    }
    deinit {
        MainActor.assumeIsolated {
            bestEffortDeinitCleanup()
        }
    }
    func registration(for command: GlobalCaptureShortcutCommand) -> GlobalCaptureShortcutRegistration {
        guard case .registered(let shortcut) = registrationStates[command] else {
            return registrationStates[command] ?? .disabled
        }
        guard hasCoherentOwnership(for: command, shortcut: shortcut) else {
            registrationStates[command] = .failed(shortcut)
            _ = unregisterOwnedRegistration(command)
            removeEventHandlerIfUnused()
            diagnosticHandler("registrationOwnership", "inconsistent", 1)
            return .failed(shortcut)
        }
        return .registered(shortcut)
    }
    func rebind(
        _ command: GlobalCaptureShortcutCommand,
        to shortcut: GlobalCaptureShortcut?
    ) -> GlobalCaptureShortcutRegistration {
        guard unregisterOwnedRegistration(command) else {
            let failedShortcut = shortcut ?? registrations[command]?.shortcut
            let result = failedShortcut.map(GlobalCaptureShortcutRegistration.failed) ?? .disabled
            registrationStates[command] = result
            notifyChange()
            return result
        }
        guard let shortcut else {
            registrationStates[command] = .disabled
            removeEventHandlerIfUnused()
            notifyChange()
            return .disabled
        }
        guard installEventHandlerIfNeeded() else {
            let result = GlobalCaptureShortcutRegistration.failed(shortcut)
            registrationStates[command] = result
            notifyChange()
            return result
        }
        let identifier = commandIdentifier(command)
        let identifierValue = hotKeyID(for: command)
        var reference: EventHotKeyRef?
        let status = api.registerEventHotKey(
            shortcut,
            identifierValue,
            Self.exclusiveRegistrationOptions,
            &reference
        )
        statusHandler("RegisterEventHotKey", status)
        let result: GlobalCaptureShortcutRegistration
        if status == noErr, let reference {
            registrations[command] = Registration(reference: reference, shortcut: shortcut)
            commandByID[identifier] = command
            result = .registered(shortcut)
        } else if status == eventHotKeyExistsErr {
            result = .conflict(shortcut)
            removeEventHandlerIfUnused()
        } else {
            result = .failed(shortcut)
            removeEventHandlerIfUnused()
        }
        registrationStates[command] = result
        notifyChange()
        return result
    }
    func unregister(_ command: GlobalCaptureShortcutCommand) {
        if unregisterOwnedRegistration(command) {
            registrationStates[command] = .disabled
            removeEventHandlerIfUnused()
        } else if let shortcut = registrations[command]?.shortcut {
            registrationStates[command] = .failed(shortcut)
        }
        notifyChange()
    }
    func shutdown() {
        for command in GlobalCaptureShortcutCommand.allCases {
            if unregisterOwnedRegistration(command) {
                registrationStates[command] = .disabled
            } else if let shortcut = registrations[command]?.shortcut {
                registrationStates[command] = .failed(shortcut)
            }
        }
        removeEventHandlerIfUnused()
        _ = removePartialEventHandlerIfNeeded()
        onRegistrationChanged = nil
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
    /// Stable feature-owned identifier used by in-process Carbon integration tests.
    func hotKeyID(for command: GlobalCaptureShortcutCommand) -> EventHotKeyID {
        EventHotKeyID(signature: Self.signature, id: commandIdentifier(command))
    }
    /// Corrupts only the test coherence probe while retaining real resources for safe reconciliation.
    func simulateMissingEventHandlerOwnershipForTesting() {
        eventHandlerOwnershipValidForTesting = false
    }
    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandler != nil, eventHandlerContext != nil, eventHandlerOwnershipValidForTesting {
            return true
        }
        guard eventHandler == nil, eventHandlerContext == nil else { return false }
        guard removePartialEventHandlerIfNeeded() else { return false }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let context = Unmanaged.passRetained(CallbackContext(manager: self)).toOpaque()
        let status = api.installEventHandler(
            &eventType,
            Self.eventHandlerCallback,
            context,
            &installedHandler
        )
        lastInstallEventHandlerStatus = status
        statusHandler("InstallEventHandler", status)
        guard status == noErr, let installedHandler else {
            if let installedHandler {
                partialEventHandler = installedHandler
                partialEventHandlerContext = context
                _ = removePartialEventHandlerIfNeeded()
            } else {
                releaseContext(context)
            }
            return false
        }
        eventHandler = installedHandler
        eventHandlerContext = context
        eventHandlerOwnershipValidForTesting = true
        return true
    }
    private func unregisterOwnedRegistration(_ command: GlobalCaptureShortcutCommand) -> Bool {
        guard let registration = registrations[command] else {
            commandByID.removeValue(forKey: commandIdentifier(command))
            return true
        }
        let status = api.unregisterEventHotKey(registration.reference)
        lastUnregisterEventHotKeyStatus = status
        statusHandler("UnregisterEventHotKey", status)
        guard status == noErr else { return false }
        registrations.removeValue(forKey: command)
        commandByID.removeValue(forKey: commandIdentifier(command))
        return true
    }
    private func removeEventHandlerIfUnused() {
        guard registrations.isEmpty, let eventHandler else { return }
        let status = api.removeEventHandler(eventHandler)
        lastRemoveEventHandlerStatus = status
        statusHandler("RemoveEventHandler", status)
        guard status == noErr else { return }
        self.eventHandler = nil
        eventHandlerOwnershipValidForTesting = true
        if let eventHandlerContext {
            self.eventHandlerContext = nil
            releaseContext(eventHandlerContext)
        }
    }
    @discardableResult
    private func removePartialEventHandlerIfNeeded() -> Bool {
        guard let partialEventHandler else { return true }
        let status = api.removeEventHandler(partialEventHandler)
        lastRemoveEventHandlerStatus = status
        statusHandler("RemoveEventHandler", status)
        guard status == noErr else { return false }
        self.partialEventHandler = nil
        if let partialEventHandlerContext {
            self.partialEventHandlerContext = nil
            releaseContext(partialEventHandlerContext)
        }
        return true
    }
    private static let eventHandlerCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()
        return MainActor.assumeIsolated {
            guard let manager = context.manager else { return OSStatus(eventNotHandledErr) }
            return manager.handleEvent(event)
        }
    }
    private func handleEvent(_ event: EventRef) -> OSStatus {
        callbackCount &+= 1
        var identifier = EventHotKeyID()
        let status = api.readEventHotKeyID(event, &identifier)
        diagnosticHandler("hotKeyCallback", status == noErr ? "received" : "readFailed", callbackCount)
        guard status == noErr else { return status }
        return routeHotKey(id: identifier)
    }
    private func routeHotKey(id: EventHotKeyID) -> OSStatus {
        guard id.signature == Self.signature,
              let command = commandByID[id.id] else {
            diagnosticHandler("commandDispatch", "unhandled", dispatchCount)
            return OSStatus(eventNotHandledErr)
        }
        dispatchCount &+= 1
        commandHandler(command)
        diagnosticHandler("commandDispatch", "dispatched", dispatchCount)
        return noErr
    }
    private func commandIdentifier(_ command: GlobalCaptureShortcutCommand) -> UInt32 {
        UInt32((GlobalCaptureShortcutCommand.allCases.firstIndex(of: command) ?? 0) + 1)
    }
    private func hasCoherentOwnership(
        for command: GlobalCaptureShortcutCommand,
        shortcut: GlobalCaptureShortcut
    ) -> Bool {
        guard eventHandler != nil,
              eventHandlerContext != nil,
              eventHandlerOwnershipValidForTesting,
              let registration = registrations[command],
              registration.shortcut == shortcut else {
            return false
        }
        return commandByID[commandIdentifier(command)] == command
    }
    private func bestEffortDeinitCleanup() {
        for command in GlobalCaptureShortcutCommand.allCases {
            _ = unregisterOwnedRegistration(command)
        }
        if let eventHandler {
            let status = api.removeEventHandler(eventHandler)
            lastRemoveEventHandlerStatus = status
            statusHandler("RemoveEventHandler", status)
            if status == noErr, let eventHandlerContext {
                self.eventHandlerContext = nil
                releaseContext(eventHandlerContext)
            }
            self.eventHandler = nil
        }
        if let partialEventHandler {
            let status = api.removeEventHandler(partialEventHandler)
            lastRemoveEventHandlerStatus = status
            statusHandler("RemoveEventHandler", status)
            if status == noErr, let partialEventHandlerContext {
                self.partialEventHandlerContext = nil
                releaseContext(partialEventHandlerContext)
            }
            self.partialEventHandler = nil
        }
        // On removal failure the pass-retained context intentionally remains alive. It holds only
        // a weak manager reference, so a late Carbon callback safely returns eventNotHandledErr.
    }
    private func releaseContext(_ context: UnsafeMutableRawPointer) {
        Unmanaged<CallbackContext>.fromOpaque(context).release()
    }
    private func notifyChange() {
        onRegistrationChanged?()
    }
}
