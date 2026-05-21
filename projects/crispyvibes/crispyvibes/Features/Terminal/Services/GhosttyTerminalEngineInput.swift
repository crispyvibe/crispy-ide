import AppKit
import Foundation
import GhosttyKit

@MainActor
extension GhosttyTerminalEngine {
    func startProcess(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String
    ) {
        pendingExitCode = nil
        lastVisibleContents = ""
        hasReportedRenderableOutput = false
        hasAttemptedInitialBannerCleanup = false
        clearPendingTextQueue()
        executablePath = executable
        launchArgs = args
        launchEnvironment = environment
        currentDirectoryPath = currentDirectory
        started = true
        hasObservedInteractivePrompt = false
        isLightweightTracking = false
        lastVisibleContentsHash = 0
        guard terminalServices.ghosttyRuntime.isAvailable else { return }
        applyThemeOverrideIfPossible()
        if terminalView.window != nil {
            terminalView.createSurfaceIfNeeded()
        }
        terminalView.setDesiredGridSize(columns: preferredColumns, rows: preferredRows, font: font)
        captureVisibleContentsIfNeeded()
    }

    func terminate() {
        pendingRendererRecoveryWorkItem?.cancel()
        pendingRendererRecoveryWorkItem = nil
        started = false
        stopOutputPolling()
        lastVisibleContents = ""
        clearPendingTextQueue()
        terminalView.destroySurface()
        handleProcessExit(exitCode: pendingExitCode)
        actionHandlers = TerminalSessionActionHandlers()
    }

    func send(text: String) {
        guard !text.isEmpty else { return }
        // Split trailing \r or \n into a separate Enter key event,
        // because ghostty_surface_text (IME/paste path) does not
        // pass control characters through to the PTY.
        let needsEnter = text.hasSuffix("\r") || text.hasSuffix("\n")
        let body = needsEnter ? String(text.dropLast()) : text
        if !body.isEmpty, let data = body.data(using: .utf8) {
            guard let surface else {
                enqueuePendingText(data)
                if needsEnter { enqueuePendingEnter() }
                return
            }
            writeTextData(data, to: surface)
        }
        if needsEnter {
            guard let surface else {
                enqueuePendingEnter()
                return
            }
            sendEnterKey(to: surface)
        }
    }

    func sendControlKey(
        to surface: ghostty_surface_t,
        keycode: UInt32,
        mods: ghostty_input_mods_e,
        text: String,
        unshiftedCodepoint: UInt32
    ) {
        sendKey(
            to: surface,
            keycode: keycode,
            mods: mods,
            text: text.isEmpty ? nil : text,
            unshiftedCodepoint: unshiftedCodepoint
        )
    }

    func typeCharacters(_ text: String) {
        guard let surface = terminalView.surface else { return }
        for char in text {
            let str = String(char)
            var key = ghostty_input_key_s()
            key.action = GHOSTTY_ACTION_PRESS
            key.mods = GHOSTTY_MODS_NONE
            key.consumed_mods = GHOSTTY_MODS_NONE
            key.keycode = UInt32(GHOSTTY_KEY_UNIDENTIFIED.rawValue)
            key.unshifted_codepoint = str.unicodeScalars.first?.value ?? 0
            key.composing = false
            str.withCString { pointer in
                key.text = pointer
                _ = ghostty_surface_key(surface, key)
            }
            key.action = GHOSTTY_ACTION_RELEASE
            key.text = nil
            _ = ghostty_surface_key(surface, key)
        }
    }

    func pressEnter() {
        guard let surface = terminalView.surface else {
            enqueuePendingEnter()
            return
        }
        sendEnterKey(to: surface)
    }

    func pressSubmitVariant(_ variant: TerminalSubmitVariant) {
        guard let surface = terminalView.surface else {
            switch variant {
            case .returnKey, .keypadEnter, .controlM, .carriageReturnByte:
                enqueuePendingEnter()
            case .controlJ, .lineFeedByte:
                enqueuePendingText(Data([0x0A]))
            }
            return
        }

        switch variant {
        case .returnKey:
            sendEnterKey(to: surface)
        case .keypadEnter:
            sendKey(
                to: surface,
                keycode: macOSKeypadEnterKeyCode,
                text: "\r",
                unshiftedCodepoint: 0x0D
            )
        case .controlJ:
            sendKey(
                to: surface,
                keycode: macOSJKeyCode,
                mods: GHOSTTY_MODS_CTRL,
                text: "j",
                unshiftedCodepoint: 0x6A
            )
        case .controlM:
            sendKey(
                to: surface,
                keycode: macOSMKeyCode,
                mods: GHOSTTY_MODS_CTRL,
                text: "m",
                unshiftedCodepoint: 0x6D
            )
        case .lineFeedByte:
            writeRawSubmitByte(0x0A, to: surface)
        case .carriageReturnByte:
            writeRawSubmitByte(0x0D, to: surface)
        }
    }

    func flushPendingTextIfNeeded() {
        guard let surface, !pendingTextQueue.isEmpty else { return }
        let queued = pendingTextQueue
        clearPendingTextQueue()

        for chunk in queued {
            if isQueuedEnterMarker(chunk) {
                sendEnterKey(to: surface)
            } else {
                writeTextData(chunk, to: surface)
            }
        }
    }

    private func sendKey(
        to surface: ghostty_surface_t,
        keycode: UInt32,
        mods: ghostty_input_mods_e = GHOSTTY_MODS_NONE,
        text: String?,
        unshiftedCodepoint: UInt32
    ) {
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.mods = mods
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.keycode = keycode
        key.unshifted_codepoint = unshiftedCodepoint
        key.composing = false
        if let text {
            text.withCString { pointer in
                key.text = pointer
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            key.text = nil
            _ = ghostty_surface_key(surface, key)
        }
        key.action = GHOSTTY_ACTION_RELEASE
        key.text = nil
        _ = ghostty_surface_key(surface, key)
    }

    private func sendEnterKey(to surface: ghostty_surface_t) {
        sendKey(
            to: surface,
            keycode: macOSReturnKeyCode,
            text: "\r",
            unshiftedCodepoint: 0x0D
        )
    }

    private func writeRawSubmitByte(_ byte: UInt8, to surface: ghostty_surface_t) {
        writeTextData(Data([byte]), to: surface)
    }

    private func writeTextData(_ data: Data, to surface: ghostty_surface_t) {
        data.withUnsafeBytes { rawBuffer in
            guard let pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return
            }
            ghostty_surface_text(surface, pointer, UInt(rawBuffer.count))
        }
    }

    private func enqueuePendingText(_ data: Data) {
        let incomingBytes = data.count
        while !pendingTextQueue.isEmpty && pendingTextBytes + incomingBytes > maxPendingTextBytes {
            let dropped = pendingTextQueue.removeFirst()
            pendingTextBytes -= dropped.count
        }

        pendingTextQueue.append(data)
        pendingTextBytes += incomingBytes
    }

    private func enqueuePendingEnter() {
        enqueuePendingText(queuedEnterMarker)
    }

    private func clearPendingTextQueue() {
        pendingTextQueue.removeAll(keepingCapacity: false)
        pendingTextBytes = 0
    }

    private func isQueuedEnterMarker(_ data: Data) -> Bool {
        data == queuedEnterMarker
    }
}
