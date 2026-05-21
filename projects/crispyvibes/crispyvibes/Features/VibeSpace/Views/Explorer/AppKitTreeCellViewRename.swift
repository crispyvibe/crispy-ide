import AppKit

extension AppKitTreeCellView {
    func beginRenameMode(for item: FileItem) {
        isInRenameMode = true
        hasQueuedRenameFocus = true
        didDispatchRenameEndAction = false
        applyLabelAccessibilityIdentifier()
        labelField.isEditable = true
        labelField.isSelectable = true
        labelField.isBordered = true
        labelField.drawsBackground = true
        labelField.delegate = self
        labelField.lineBreakMode = .byClipping
        chevronButton.isEnabled = false

        if !ensureRenameFieldFocused() {
            attemptRenameFocus(for: item, retryCount: 0)
        }
    }

    @discardableResult
    func ensureRenameFieldFocused() -> Bool {
        guard isInRenameMode, let window else { return false }

        if let editor = window.firstResponder as? NSTextView,
           editor.delegate === labelField {
            hasQueuedRenameFocus = false
            return true
        }

        guard window.makeFirstResponder(labelField),
              let editor = window.fieldEditor(true, for: labelField) else {
            return false
        }

        labelField.selectText(nil)
        if let item = currentNode?.item {
            selectRenameRange(in: editor, for: item)
        }
        hasQueuedRenameFocus = false
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        publishRenameTextDidChange()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isInRenameMode else { return }
        let movement = (obj.userInfo?["NSTextMovement"] as? NSNumber)?.intValue ?? Int.min
        let shouldIgnoreIllegalEndEditing =
            movement == 0 &&
            ((window?.firstResponder as? NSTextView)?.delegate === labelField)
        if shouldIgnoreIllegalEndEditing {
            return
        }
        dispatchRenameEndActionIfNeeded()
        finishRenameMode()
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        dispatchRenameEndActionIfNeeded()
        return true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            currentAction?(.cancelRename)
            cancelRenameMode()
            return true
        }
        return false
    }

    private func attemptRenameFocus(for item: FileItem, retryCount: Int) {
        guard retryCount < 5, isInRenameMode else { return }
        let delay: TimeInterval = retryCount == 0 ? 0 : 0.03
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isInRenameMode else { return }
            guard self.window != nil else {
                self.attemptRenameFocus(for: item, retryCount: retryCount + 1)
                return
            }
            guard self.ensureRenameFieldFocused() else {
                self.attemptRenameFocus(for: item, retryCount: retryCount + 1)
                return
            }
        }
    }

    private func selectRenameRange(in editor: NSText, for item: FileItem) {
        let name = item.displayName as NSString
        if !item.isDirectory {
            let extensionRange = name.range(of: ".", options: .backwards)
            if extensionRange.location != NSNotFound && extensionRange.location > 0 {
                editor.selectedRange = NSRange(location: 0, length: extensionRange.location)
                return
            }
        }
        editor.selectedRange = NSRange(location: 0, length: name.length)
    }

    private func finishRenameMode() {
        isInRenameMode = false
        hasQueuedRenameFocus = false
        applyLabelAccessibilityIdentifier()
        labelField.isEditable = false
        labelField.isSelectable = false
        labelField.isBordered = false
        labelField.drawsBackground = false
        labelField.delegate = nil
        labelField.lineBreakMode = .byTruncatingTail
        chevronButton.isEnabled = currentNode?.item.isDirectory == true
    }

    func cancelRenameMode() {
        finishRenameMode()
        labelField.abortEditing()
    }

    private func dispatchRenameEndActionIfNeeded() {
        guard !didDispatchRenameEndAction, let node = currentNode else { return }
        didDispatchRenameEndAction = true

        let newName = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != node.item.displayName {
            renameTextSetter?(newName)
            currentAction?(.commitRename)
        } else {
            currentAction?(.cancelRename)
        }
    }

    private func publishRenameTextDidChange() {
        let updatedText = labelField.stringValue
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRenameInteractionActive else { return }
            self.renameTextSetter?(updatedText)
        }
    }

    func applyLabelAccessibilityIdentifier() {
        let identifier = isInRenameMode ? "explorer.rename.field" : "explorer.row.label"
        labelField.setAccessibilityIdentifier(identifier)
    }
}
