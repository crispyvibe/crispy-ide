import AppKit
import Carbon
import Foundation
import GhosttyKit

@MainActor
extension GhosttyTerminalView: @preconcurrency NSTextInputClient {}

private enum GhosttyKeyboardLayout {
    static var id: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let sourceIDPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }

        let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPointer).takeUnretainedValue()
        return sourceID as String
    }

    static func character(
        forKeyCode keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            translationModifierKeyState(for: modifierFlags),
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).lowercased()
    }

    private static func translationModifierKeyState(for modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        let normalized = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .command])

        var carbonModifiers: Int = 0
        if normalized.contains(.shift) {
            carbonModifiers |= shiftKey
        }
        if normalized.contains(.command) {
            carbonModifiers |= cmdKey
        }

        return UInt32((carbonModifiers >> 8) & 0xFF)
    }
}

@MainActor
extension GhosttyTerminalView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        false
    }

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    @objc func copy(_ sender: Any?) {
        guard let sessionID = engine?.sessionID,
              engine?.terminalServices.focusCoordinator.currentSessionID == sessionID else {
            nextResponder?.tryToPerform(#selector(copy(_:)), with: sender)
            return
        }
        engine?.copySelection()
    }

    @objc func paste(_ sender: Any?) {
        guard let sessionID = engine?.sessionID,
              engine?.terminalServices.focusCoordinator.currentSessionID == sessionID else {
            nextResponder?.tryToPerform(#selector(paste(_:)), with: sender)
            return
        }
        engine?.pasteFromClipboard()
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        if consumeInlineTriggerCommand(for: event) {
            return
        }

        if consumeInlineTriggerText(for: event) {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.control), !flags.contains(.command), !flags.contains(.option), !hasMarkedText() {
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
            keyEvent.keycode = UInt32(event.keyCode)
            keyEvent.mods = mods(from: event)
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
            keyEvent.composing = false

            let baseText = event.charactersIgnoringModifiers ?? event.characters ?? ""
            let handled: Bool
            if shouldSendText(baseText) {
                handled = baseText.withCString { pointer in
                    keyEvent.text = pointer
                    return ghostty_surface_key(surface, keyEvent)
                }
            } else {
                keyEvent.text = nil
                handled = ghostty_surface_key(surface, keyEvent)
            }
            if handled {
                return
            }
        }

        let translationModsGhostty = ghostty_surface_key_translation_mods(surface, mods(from: event))
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            let hasFlag: Bool
            switch flag {
            case .shift:
                hasFlag = (translationModsGhostty.rawValue & GHOSTTY_MODS_SHIFT.rawValue) != 0
            case .control:
                hasFlag = (translationModsGhostty.rawValue & GHOSTTY_MODS_CTRL.rawValue) != 0
            case .option:
                hasFlag = (translationModsGhostty.rawValue & GHOSTTY_MODS_ALT.rawValue) != 0
            case .command:
                hasFlag = (translationModsGhostty.rawValue & GHOSTTY_MODS_SUPER.rawValue) != 0
            default:
                hasFlag = translationMods.contains(flag)
            }
            if hasFlag {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        let markedTextBefore = hasMarkedText()
        let keyboardIDBefore = !markedTextBefore ? GhosttyKeyboardLayout.id : nil
        interpretKeyEvents([translationEvent])
        if !markedTextBefore, let keyboardIDBefore, keyboardIDBefore != GhosttyKeyboardLayout.id {
            syncPreedit(clearIfNeeded: markedTextBefore)
            return
        }
        syncPreedit(clearIfNeeded: markedTextBefore)

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = mods(from: event)
        keyEvent.consumed_mods = consumedMods(from: translationMods)
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
        keyEvent.composing = hasMarkedText() || markedTextBefore

        let accumulatedText = keyTextAccumulator ?? []
        var deliveredAccumulatedText: [String] = []
        if !accumulatedText.isEmpty {
            keyEvent.composing = false
            for text in accumulatedText {
                if consumeInlineTriggerText(text) {
                    continue
                }
                deliveredAccumulatedText.append(text)
                if shouldSendText(text) {
                    text.withCString { pointer in
                        keyEvent.text = pointer
                        _ = ghostty_surface_key(surface, keyEvent)
                    }
                } else {
                    keyEvent.text = nil
                    _ = ghostty_surface_key(surface, keyEvent)
                }
            }
        } else if let text = keyText(for: translationEvent) {
            if consumeInlineTriggerText(text) {
                return
            }
            let suppressShiftSpaceFallbackText = shouldSuppressShiftSpaceFallbackText(
                event: translationEvent,
                markedTextBefore: markedTextBefore
            )
            if shouldSendText(text), !suppressShiftSpaceFallbackText {
                text.withCString { pointer in
                    keyEvent.text = pointer
                    _ = ghostty_surface_key(surface, keyEvent)
                }
                forwardToInsightObserver(text)
            } else {
                keyEvent.text = nil
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }

        // Forward to Terminal Insight observer. Path 1 (accumulatedText) already
        // forwarded each text fragment via `deliveredAccumulatedText`. Path 2
        // forwards inline above. On Enter, finalize the observer's buffer; the
        // observer publishes `.visible(...)` or `.sensitive` and the
        // TerminalSession's compose-history subscription picks it up — there is
        // no separate raw-text fallback here. F001-T06.
        if !deliveredAccumulatedText.isEmpty {
            for text in deliveredAccumulatedText { forwardToInsightObserver(text) }
            if event.keyCode == 36 || event.keyCode == 76 {
                forwardToInsightObserver("\n")
            }
        } else if event.keyCode == 36 || event.keyCode == 76 {
            forwardToInsightObserver("\n")
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = mods(from: event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
        keyEvent.text = nil
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else {
            super.flagsChanged(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = !flags.subtracting([.capsLock, .numericPad, .function]).isEmpty
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = hasModifier ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = mods(from: event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.unshifted_codepoint = 0
        keyEvent.text = nil
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)

        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            updateHoveredInteractiveTarget(at: point, modifierFlags: event.modifierFlags)
        } else {
            clearHoveredInteractiveTarget()
        }
    }

    func mods(from event: NSEvent) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if event.modifierFlags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if event.modifierFlags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if event.modifierFlags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if event.modifierFlags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    func consumedMods(from modifierFlags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if modifierFlags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if modifierFlags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    func unshiftedCodepoint(from event: NSEvent) -> UInt32 {
        if let layoutChars = GhosttyKeyboardLayout.character(forKeyCode: event.keyCode),
           layoutChars.count == 1,
           let layoutScalar = layoutChars.unicodeScalars.first,
           layoutScalar.value >= 0x20,
           !(layoutScalar.value >= 0xF700 && layoutScalar.value <= 0xF8FF) {
            return layoutScalar.value
        }

        let characters =
            event.characters(byApplyingModifiers: []) ??
            event.charactersIgnoringModifiers ??
            event.characters ??
            ""
        return characters.unicodeScalars.first?.value ?? 0
    }

    func keyText(for event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty else {
            return nil
        }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if scalar.value < 0x20 {
                if flags.contains(.control) {
                    return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
                }

                if scalar.value == 0x1B,
                   flags == [.shift],
                   event.charactersIgnoringModifiers == "`" {
                    return "~"
                }
                return nil
            }
        }
        if let scalar = characters.unicodeScalars.first,
           scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
            return nil
        }
        return characters
    }

    override func doCommand(by selector: Selector) {
        _ = selector
        // Let the main keyDown path send terminal key events. Doing it here as well
        // duplicates Return/Delete/Escape/navigation keys after interpretKeyEvents.
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        _ = replacementRange
        var text = ""
        if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else if let plain = string as? NSString {
            text = plain as String
        } else {
            return
        }

        unmarkText()
        guard !text.isEmpty else { return }

        if consumeInlineTriggerText(text) {
            return
        }

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
            return
        }

        sendCommittedTextToSurface(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        _ = replacementRange
        if let attributed = string as? NSAttributedString {
            markedTextStorage = attributed
        } else if let text = string as? NSString {
            markedTextStorage = NSAttributedString(string: text as String)
        } else {
            markedTextStorage = nil
        }
        markedSelectionRange = selectedRange
        updateMarkedTextInSurface()
    }

    func unmarkText() {
        markedTextStorage = nil
        markedSelectionRange = NSRange(location: NSNotFound, length: 0)
        updateMarkedTextInSurface()
    }

    func selectedRange() -> NSRange {
        if hasMarkedText() {
            return markedSelectionRange
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        guard let markedTextStorage else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedTextStorage.length)
    }

    func hasMarkedText() -> Bool {
        guard let markedTextStorage else { return false }
        return markedTextStorage.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let markedTextStorage, NSMaxRange(range) <= markedTextStorage.length else { return nil }
        actualRange?.pointee = range
        return markedTextStorage.attributedSubstring(from: range)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        return imeScreenRect(fallbackRange: range)
    }

    func characterIndex(for point: NSPoint) -> Int {
        _ = point
        return NSNotFound
    }

    private func consumeInlineTriggerText(_ text: String) -> Bool {
        engine?.actionHandlers.onInlineTriggerTextInput?(text) == true
    }

    private func consumeInlineTriggerText(for event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let effectiveFlags = flags.subtracting([.capsLock, .numericPad, .function])
        guard effectiveFlags.isEmpty || effectiveFlags == [.shift] else { return false }
        guard let text = keyText(for: event) ?? event.characters, !text.isEmpty else { return false }
        return consumeInlineTriggerText(text)
    }

    private func consumeInlineTriggerCommand(for event: NSEvent) -> Bool {
        guard let command = inlineTriggerCommand(for: event) else { return false }
        return engine?.actionHandlers.onInlineTriggerCommand?(command) == true
    }

    private func inlineTriggerCommand(for event: NSEvent) -> TerminalInlineTriggerCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let effectiveFlags = flags.subtracting([.capsLock, .numericPad, .function])
        guard effectiveFlags.isEmpty else { return nil }

        switch event.keyCode {
        case 126:
            return .moveUp
        case 125:
            return .moveDown
        case 124:
            return .moveRight
        case 36, 48, 76:
            return .confirm
        case 51:
            return .deleteBackward
        case 53:
            return .dismiss
        default:
            return nil
        }
    }

    private func shouldSendText(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return scalar.value >= 0x20
    }

    private func shouldSuppressShiftSpaceFallbackText(
        event: NSEvent,
        markedTextBefore: Bool
    ) -> Bool {
        guard event.keyCode == 49 else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.shift] else { return false }
        guard !markedTextBefore, !hasMarkedText() else { return false }
        return true
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }

        if let markedTextStorage, markedTextStorage.length > 0 {
            let string = markedTextStorage.string
            let length = string.utf8CString.count
            if length > 0 {
                string.withCString { pointer in
                    ghostty_surface_preedit(surface, pointer, UInt(length - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    private func sendCommittedTextToSurface(_ text: String) {
        if let committedTextSinkForTesting {
            committedTextSinkForTesting(text)
            return
        }
        guard let surface else { return }
        text.withCString { pointer in
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = GHOSTTY_ACTION_PRESS
            keyEvent.keycode = 0
            keyEvent.mods = GHOSTTY_MODS_NONE
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.text = pointer
            keyEvent.composing = false
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    private func forwardToInsightObserver(_ text: String) {
        guard let session = engine?.delegate as? TerminalSession else { return }
        session.insightObserver?.recordTypedKeystroke(text)
    }
}
