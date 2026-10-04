import AppKit
import Foundation

/// AppKit origin adapter that retains an ephemeral application capability but no application name.
@MainActor
final class ScreenCaptureOriginAppAdapter: OriginFocusTracking {
    private let workspace: NSWorkspace
    private let currentApplication: NSRunningApplication
    private let currentProcessID: pid_t
    private let keyWindowProvider: () -> NSWindow?

    init(
        workspace: NSWorkspace,
        currentApplication: NSRunningApplication,
        currentProcessID: pid_t,
        keyWindowProvider: @escaping () -> NSWindow?
    ) {
        self.workspace = workspace
        self.currentApplication = currentApplication
        self.currentProcessID = currentProcessID
        self.keyWindowProvider = keyWindowProvider
    }

    func captureOrigin() -> OriginFocusContext? {
        guard let frontmost = workspace.frontmostApplication else { return nil }
        if frontmost.processIdentifier == currentProcessID {
            let keyWindow = keyWindowProvider()
            return OriginFocusContext(
                application: currentApplication,
                keyWindow: keyWindow,
                firstResponder: keyWindow?.firstResponder
            )
        }
        return OriginFocusContext(application: frontmost, keyWindow: nil, firstResponder: nil)
    }

    func restoreIfNeeded(_ context: OriginFocusContext) {
        guard !context.isTerminated else { return }
        let frontmostPID = workspace.frontmostApplication?.processIdentifier
        guard frontmostPID == nil || frontmostPID == currentProcessID else { return }
        _ = context.application.activate(options: [])
        if context.processIdentifier == currentProcessID,
           let window = context.keyWindow,
           let responder = context.firstResponder {
            window.makeFirstResponder(responder)
        }
    }
}
