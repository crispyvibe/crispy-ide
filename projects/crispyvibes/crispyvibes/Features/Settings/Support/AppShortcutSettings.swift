import AppKit
import Foundation

enum AppShortcutSection: String, CaseIterable, Identifiable {
    case vibespace
    case board
    case projects
    case editor
    case appearance
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibespace:
            return "VibeSpace"
        case .board:
            return "Terminal Board"
        case .projects:
            return "Projects"
        case .editor:
            return "Editor"
        case .appearance:
            return "Appearance"
        case .app:
            return "App"
        }
    }
}

enum AppShortcutAction: String, CaseIterable, Identifiable, Codable {
    case saveDocument
    case findInDocument
    case replaceInDocument
    case openDetailedVibeSpaceView
    case openTerminalOnlyVibeSpaceView
    case toggleVibeCast
    case focusNextProject
    case focusPreviousProject
    case focusProject1
    case focusProject2
    case focusProject3
    case focusProject4
    case focusProject5
    case focusProject6
    case focusProject7
    case focusProject8
    case focusProject9
    case focusNextProjectTerminal
    case focusPreviousProjectTerminal
    case boardNavigateLeft
    case boardNavigateRight
    case boardMoveProjectToNewWindow
    case boardRecallProjectFromWindow
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize
    case openSettings
    case openDeveloperTools
    case quickCaptureTodo

    var id: String { rawValue }
}

enum AppShortcutKeyCode {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let h: UInt16 = 4
    static let z: UInt16 = 6
    static let x: UInt16 = 7
    static let c: UInt16 = 8
    static let t: UInt16 = 17
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let six: UInt16 = 22
    static let five: UInt16 = 23
    static let equal: UInt16 = 24
    static let nine: UInt16 = 25
    static let seven: UInt16 = 26
    static let minus: UInt16 = 27
    static let eight: UInt16 = 28
    static let zero: UInt16 = 29
    static let rightBracket: UInt16 = 30
    static let leftBracket: UInt16 = 33
    static let v: UInt16 = 9
    static let b: UInt16 = 11
    static let m: UInt16 = 46
    static let comma: UInt16 = 43
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

struct AppShortcutBinding: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = Self.normalizedModifierFlags(modifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    func matches(_ event: NSEvent) -> Bool {
        keyCode == event.keyCode
            && modifierFlags == Self.normalizedModifierFlags(event.modifierFlags)
    }

    var displayString: String {
        "\(modifierGlyphs)\(keyName)"
    }

    private var modifierGlyphs: String {
        var pieces: [String] = []
        if modifierFlags.contains(.control) { pieces.append("⌃") }
        if modifierFlags.contains(.option) { pieces.append("⌥") }
        if modifierFlags.contains(.shift) { pieces.append("⇧") }
        if modifierFlags.contains(.command) { pieces.append("⌘") }
        return pieces.joined()
    }

    private var keyName: String {
        switch keyCode {
        case AppShortcutKeyCode.leftArrow:
            return "←"
        case AppShortcutKeyCode.rightArrow:
            return "→"
        case AppShortcutKeyCode.upArrow:
            return "↑"
        case AppShortcutKeyCode.downArrow:
            return "↓"
        case AppShortcutKeyCode.leftBracket:
            return "["
        case AppShortcutKeyCode.rightBracket:
            return "]"
        case AppShortcutKeyCode.equal:
            return "="
        case AppShortcutKeyCode.minus:
            return "-"
        case AppShortcutKeyCode.comma:
            return ","
        case AppShortcutKeyCode.zero:
            return "0"
        case AppShortcutKeyCode.one:
            return "1"
        case AppShortcutKeyCode.two:
            return "2"
        case AppShortcutKeyCode.three:
            return "3"
        case AppShortcutKeyCode.four:
            return "4"
        case AppShortcutKeyCode.five:
            return "5"
        case AppShortcutKeyCode.six:
            return "6"
        case AppShortcutKeyCode.seven:
            return "7"
        case AppShortcutKeyCode.eight:
            return "8"
        case AppShortcutKeyCode.nine:
            return "9"
        case AppShortcutKeyCode.s:
            return "S"
        case AppShortcutKeyCode.a:
            return "A"
        case AppShortcutKeyCode.c:
            return "C"
        case AppShortcutKeyCode.d:
            return "D"
        case AppShortcutKeyCode.f:
            return "F"
        case AppShortcutKeyCode.h:
            return "H"
        case AppShortcutKeyCode.t:
            return "T"
        case AppShortcutKeyCode.v:
            return "V"
        case AppShortcutKeyCode.x:
            return "X"
        case AppShortcutKeyCode.z:
            return "Z"
        default:
            return "Key \(keyCode)"
        }
    }

    static func normalizedModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .shift, .control])
    }
}

enum AppShortcutRouting {
    private static let reservedTextEditingBindings: [AppShortcutBinding] = [
        .init(keyCode: AppShortcutKeyCode.x, modifiers: [.command]),
        .init(keyCode: AppShortcutKeyCode.c, modifiers: [.command]),
        .init(keyCode: AppShortcutKeyCode.v, modifiers: [.command]),
        .init(keyCode: AppShortcutKeyCode.a, modifiers: [.command]),
        .init(keyCode: AppShortcutKeyCode.z, modifiers: [.command]),
        .init(keyCode: AppShortcutKeyCode.z, modifiers: [.command, .shift])
    ]

    static func shouldInterceptAppShortcut(
        binding: AppShortcutBinding?,
        firstResponder: NSResponder?
    ) -> Bool {
        guard let binding else { return true }
        guard isReservedTextEditingBinding(binding) else { return true }
        return !isTextEditingResponder(firstResponder)
    }

    static func isReservedTextEditingBinding(_ binding: AppShortcutBinding) -> Bool {
        reservedTextEditingBindings.contains(binding)
    }

    static func isTextEditingResponder(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if responder is NSTextView {
            return true
        }
        if let view = responder as? NSView {
            let className = NSStringFromClass(type(of: view))
            if className.contains("WKContent") {
                return true
            }
        }
        return false
    }
}

struct AppShortcutPreferenceValue: Codable, Equatable {
    var isEnabled: Bool
    var binding: AppShortcutBinding?
}

struct AppShortcutDescriptor: Identifiable {
    let action: AppShortcutAction
    let title: String
    let section: AppShortcutSection
    let defaultBinding: AppShortcutBinding?
    let isEditable: Bool

    var id: AppShortcutAction { action }
}

struct AppShortcutVibeSpaceContext {
    let vibespaceName: String
    let projects: [VibeSpaceSettingsProjectItem]
    let vibespaceShortcuts: [TerminalShortcutDefinition]
    let setVibeSpaceShortcuts: ([TerminalShortcutDefinition]) -> Void
    let projectShortcutsForPath: (String) -> [TerminalShortcutDefinition]
    let setProjectShortcutsForPath: (String, [TerminalShortcutDefinition]) -> Void
}

enum AppShortcutRegistry {
    static let descriptors: [AppShortcutDescriptor] = [
        .init(action: .saveDocument, title: "Save Document", section: .editor, defaultBinding: .init(keyCode: AppShortcutKeyCode.s, modifiers: [.command]), isEditable: true),
        .init(action: .findInDocument, title: "Find in Document", section: .editor, defaultBinding: .init(keyCode: AppShortcutKeyCode.f, modifiers: [.command]), isEditable: true),
        .init(action: .replaceInDocument, title: "Replace in Document", section: .editor, defaultBinding: .init(keyCode: AppShortcutKeyCode.h, modifiers: [.command, .shift]), isEditable: true),
        .init(action: .openDetailedVibeSpaceView, title: "Open Detailed View", section: .vibespace, defaultBinding: .init(keyCode: AppShortcutKeyCode.d, modifiers: [.command]), isEditable: true),
        .init(action: .openTerminalOnlyVibeSpaceView, title: "Open Terminal Board", section: .vibespace, defaultBinding: .init(keyCode: AppShortcutKeyCode.t, modifiers: [.command]), isEditable: true),
        .init(action: .toggleVibeCast, title: "Toggle VibeCast", section: .vibespace, defaultBinding: .init(keyCode: AppShortcutKeyCode.v, modifiers: [.command, .shift]), isEditable: true),
        .init(action: .quickCaptureTodo, title: "Quick Add Todo", section: .vibespace, defaultBinding: .init(keyCode: AppShortcutKeyCode.t, modifiers: [.command, .control]), isEditable: true),
        .init(action: .focusNextProject, title: "Focus Next Project", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.rightBracket, modifiers: [.command, .option]), isEditable: true),
        .init(action: .focusPreviousProject, title: "Focus Previous Project", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.leftBracket, modifiers: [.command, .option]), isEditable: true),
        .init(action: .focusProject1, title: "Focus Project 1", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.one, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject2, title: "Focus Project 2", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.two, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject3, title: "Focus Project 3", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.three, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject4, title: "Focus Project 4", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.four, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject5, title: "Focus Project 5", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.five, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject6, title: "Focus Project 6", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.six, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject7, title: "Focus Project 7", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.seven, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject8, title: "Focus Project 8", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.eight, modifiers: [.command]), isEditable: false),
        .init(action: .focusProject9, title: "Focus Project 9", section: .projects, defaultBinding: .init(keyCode: AppShortcutKeyCode.nine, modifiers: [.command]), isEditable: false),
        .init(action: .focusNextProjectTerminal, title: "Focus Terminal Down", section: .board, defaultBinding: .init(keyCode: AppShortcutKeyCode.downArrow, modifiers: [.command, .option]), isEditable: true),
        .init(action: .focusPreviousProjectTerminal, title: "Focus Terminal Up", section: .board, defaultBinding: .init(keyCode: AppShortcutKeyCode.upArrow, modifiers: [.command, .option]), isEditable: true),
        .init(action: .boardNavigateLeft, title: "Focus Left", section: .board, defaultBinding: .init(keyCode: AppShortcutKeyCode.leftArrow, modifiers: [.command, .option]), isEditable: true),
        .init(action: .boardNavigateRight, title: "Focus Right", section: .board, defaultBinding: .init(keyCode: AppShortcutKeyCode.rightArrow, modifiers: [.command, .option]), isEditable: true),
        .init(action: .boardMoveProjectToNewWindow, title: "Move Project Panes to New Window", section: .board, defaultBinding: .init(keyCode: AppShortcutKeyCode.m, modifiers: [.command, .option]), isEditable: true),
        .init(action: .boardRecallProjectFromWindow, title: "Recall Panes to Primary Window", section: .board, defaultBinding: .init(keyCode: AppShortcutKeyCode.b, modifiers: [.command, .option]), isEditable: true),
        .init(action: .increaseFontSize, title: "Increase Font Size", section: .appearance, defaultBinding: .init(keyCode: AppShortcutKeyCode.equal, modifiers: [.command]), isEditable: true),
        .init(action: .decreaseFontSize, title: "Decrease Font Size", section: .appearance, defaultBinding: .init(keyCode: AppShortcutKeyCode.minus, modifiers: [.command]), isEditable: true),
        .init(action: .resetFontSize, title: "Reset Font Size", section: .appearance, defaultBinding: .init(keyCode: AppShortcutKeyCode.zero, modifiers: [.command]), isEditable: true),
        .init(action: .openSettings, title: "Open Settings", section: .app, defaultBinding: .init(keyCode: AppShortcutKeyCode.comma, modifiers: [.command]), isEditable: true),
        .init(action: .openDeveloperTools, title: "Open Developer Tools", section: .app, defaultBinding: .init(keyCode: AppShortcutKeyCode.d, modifiers: [.command, .option]), isEditable: true)
    ]

    private static let descriptorByAction: [AppShortcutAction: AppShortcutDescriptor] = Dictionary(
        uniqueKeysWithValues: descriptors.map { ($0.action, $0) }
    )

    static func descriptor(for action: AppShortcutAction) -> AppShortcutDescriptor {
        descriptorByAction[action]!
    }

    static func binding(for action: AppShortcutAction, userDefaults: UserDefaults = .standard) -> AppShortcutBinding? {
        let descriptor = descriptor(for: action)
        guard descriptor.isEditable else {
            return descriptor.defaultBinding
        }
        let override = preferenceValue(for: action, userDefaults: userDefaults)
        if let override {
            return override.isEnabled ? override.binding : nil
        }
        return descriptor.defaultBinding
    }

    static func action(matching event: NSEvent, userDefaults: UserDefaults = .standard) -> AppShortcutAction? {
        descriptors.first(where: { descriptor in
            guard let binding = binding(for: descriptor.action, userDefaults: userDefaults) else { return false }
            return binding.matches(event)
        })?.action
    }

    static func conflict(
        for binding: AppShortcutBinding,
        excluding excludedAction: AppShortcutAction? = nil,
        userDefaults: UserDefaults = .standard
    ) -> AppShortcutAction? {
        descriptors.first(where: { descriptor in
            descriptor.action != excludedAction
                && self.binding(for: descriptor.action, userDefaults: userDefaults) == binding
        })?.action
    }

    static func setPreferenceValue(
        _ value: AppShortcutPreferenceValue?,
        for action: AppShortcutAction,
        userDefaults: UserDefaults = .standard
    ) {
        guard descriptor(for: action).isEditable else { return }
        var overrides = loadOverrides(userDefaults: userDefaults)
        if let value {
            overrides[action.rawValue] = value
        } else {
            overrides.removeValue(forKey: action.rawValue)
        }
        if overrides.isEmpty {
            userDefaults.removeObject(forKey: AppPreferences.appShortcutOverridesKey)
            return
        }
        if let encoded = try? JSONEncoder().encode(overrides) {
            userDefaults.set(encoded, forKey: AppPreferences.appShortcutOverridesKey)
        }
    }

    static func resetAll(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: AppPreferences.appShortcutOverridesKey)
    }

    static func preferenceValue(
        for action: AppShortcutAction,
        userDefaults: UserDefaults = .standard
    ) -> AppShortcutPreferenceValue? {
        guard descriptor(for: action).isEditable else { return nil }
        return loadOverrides(userDefaults: userDefaults)[action.rawValue]
    }

    private static func loadOverrides(userDefaults: UserDefaults) -> [String: AppShortcutPreferenceValue] {
        guard let data = userDefaults.data(forKey: AppPreferences.appShortcutOverridesKey),
              let decoded = try? JSONDecoder().decode([String: AppShortcutPreferenceValue].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

struct AppShortcutSettingsRow: Identifiable {
    let action: AppShortcutAction
    let title: String
    let section: AppShortcutSection
    let defaultBinding: AppShortcutBinding?
    let currentBinding: AppShortcutBinding?
    let isCustomized: Bool
    let isEditable: Bool

    var id: AppShortcutAction { action }
}

@MainActor
final class AppShortcutSettingsStore: ObservableObject {
    @Published private(set) var rows: [AppShortcutSettingsRow] = []
    @Published var message: String?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        reload()
    }

    func reload() {
        rows = AppShortcutRegistry.descriptors.map { descriptor in
            let preferenceValue = AppShortcutRegistry.preferenceValue(for: descriptor.action, userDefaults: userDefaults)
            return AppShortcutSettingsRow(
                action: descriptor.action,
                title: descriptor.title,
                section: descriptor.section,
                defaultBinding: descriptor.defaultBinding,
                currentBinding: AppShortcutRegistry.binding(for: descriptor.action, userDefaults: userDefaults),
                isCustomized: preferenceValue != nil,
                isEditable: descriptor.isEditable
            )
        }
    }

    func setBinding(_ binding: AppShortcutBinding?, for action: AppShortcutAction) {
        guard AppShortcutRegistry.descriptor(for: action).isEditable else { return }
        if let binding,
           AppShortcutRouting.isReservedTextEditingBinding(binding) {
            message = "\"\(binding.displayString)\" is reserved for text editing."
            return
        }
        if let binding,
           let conflictingAction = AppShortcutRegistry.conflict(
            for: binding,
            excluding: action,
            userDefaults: userDefaults
           ) {
            let conflictingTitle = AppShortcutRegistry.descriptor(for: conflictingAction).title
            message = "\"\(binding.displayString)\" is already assigned to \(conflictingTitle)."
            return
        }

        AppShortcutRegistry.setPreferenceValue(
            .init(isEnabled: binding != nil, binding: binding),
            for: action,
            userDefaults: userDefaults
        )
        message = nil
        reload()
    }

    func reset(_ action: AppShortcutAction) {
        guard AppShortcutRegistry.descriptor(for: action).isEditable else { return }
        AppShortcutRegistry.setPreferenceValue(nil, for: action, userDefaults: userDefaults)
        message = nil
        reload()
    }

    func resetAll() {
        AppShortcutRegistry.resetAll(userDefaults: userDefaults)
        message = nil
        reload()
    }
}
