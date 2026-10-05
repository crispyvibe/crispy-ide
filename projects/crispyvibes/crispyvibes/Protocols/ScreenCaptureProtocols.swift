import AppKit
import Combine
import CoreGraphics
import Foundation

/// Screen Recording authorization boundary. Probes and requests occur only after explicit user action.
@MainActor
protocol ScreenCaptureAuthorizing: AnyObject {
    /// Last state inferred without consulting TCC.
    var cachedAuthorizationState: ScreenCaptureAuthorizationState { get }
    /// Explicitly probes the current TCC state.
    func authorizationStatus() -> ScreenCaptureAuthorizationState
    func requestAuthorization() -> ScreenCaptureAuthorizationState
    func openScreenRecordingSettings()
}

/// Injectable suspension boundary used by capture delays and delayed progress UI.
protocol ScreenCaptureScheduling: Sendable {
    func sleep(for duration: Duration) async throws
}

/// Production monotonic scheduler.
struct ContinuousScreenCaptureScheduler: ScreenCaptureScheduling {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Bounded race helper for non-interactive catalog and pixel-acquisition stages.
protocol ScreenCaptureStageRacing: Sendable {
    func catalog(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> ScreenCaptureCatalog
    ) async throws -> ScreenCaptureCatalog
    func capture(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> CapturedScreenImage
    ) async throws -> CapturedScreenImage
}

/// Production stage racer with generous bounds; user selection is intentionally not timed.
struct ContinuousScreenCaptureStageRacer: ScreenCaptureStageRacing {
    func catalog(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> ScreenCaptureCatalog
    ) async throws -> ScreenCaptureCatalog {
        try await race(timeout: timeout, timeoutError: .catalogUnavailable, operation: operation)
    }

    func capture(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> CapturedScreenImage
    ) async throws -> CapturedScreenImage {
        try await race(timeout: timeout, timeoutError: .captureFailed, operation: operation)
    }

    private func race<Value: Sendable>(
        timeout: Duration,
        timeoutError: ScreenCaptureError,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: timeout)
                throw timeoutError
            }
            guard let first = try await group.next() else { throw timeoutError }
            group.cancelAll()
            return first
        }
    }
}

/// Still-capture catalog and acquisition boundary.
protocol ScreenCaptureProviding: Sendable {
    func catalog() async throws -> ScreenCaptureCatalog
    func capture(
        selection: CaptureSelectionDescriptor,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws -> CapturedScreenImage
}

/// Restores capture-owned surfaces hidden behind the compositor barrier.
@MainActor
protocol ScreenCaptureHiddenSurfaceRestoring: AnyObject {
    func restore()
}

/// Current capture-UI windows that must not appear in acquired pixels.
@MainActor
protocol ScreenCaptureUIExclusionProviding: AnyObject {
    var excludedCaptureWindowIDs: Set<CGWindowID> { get }
    /// Orders out non-filterable UI and returns a token that can restore previously visible surfaces.
    func prepareForCapture() async -> any ScreenCaptureHiddenSurfaceRestoring
}

/// Read-only persisted preferences boundary supplied by F036 integration.
@MainActor
protocol ScreenCapturePreferencesProviding: AnyObject {
    var screenCapturePreferences: ScreenCapturePreferences { get }
    func updateRememberedMode(_ mode: CaptureMode)
}

/// Mutable preferences boundary used by settings without depending on a concrete store.
@MainActor
protocol ScreenCapturePreferencesManaging: ScreenCapturePreferencesProviding {
    var screenCapturePreferencesPublisher: AnyPublisher<ScreenCapturePreferences, Never> { get }
    func updateDelay(_ delay: CaptureDelay)
    func updateIncludesPointer(_ includesPointer: Bool)
    func reset()
}

/// A registered system-wide command without an event tap.
struct GlobalCaptureShortcut: Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// Typed commands accepted from F016/global registration.
enum GlobalCaptureShortcutCommand: String, CaseIterable, Sendable {
    case captureScreen
}

/// Actionable registration result used by settings.
enum GlobalCaptureShortcutRegistration: Equatable, Sendable {
    case registered(GlobalCaptureShortcut)
    case disabled
    case conflict(GlobalCaptureShortcut)
    case failed(GlobalCaptureShortcut)
}

/// Global-hotkey adapter boundary. Implementations must unregister before rebinding.
@MainActor
protocol GlobalCaptureShortcutManaging: AnyObject {
    var onRegistrationChanged: (() -> Void)? { get set }
    func registration(for command: GlobalCaptureShortcutCommand) -> GlobalCaptureShortcutRegistration
    func rebind(_ command: GlobalCaptureShortcutCommand, to shortcut: GlobalCaptureShortcut?) -> GlobalCaptureShortcutRegistration
    func unregister(_ command: GlobalCaptureShortcutCommand)
    func shutdown()
}

/// Eager full-representation encoding boundary, serialized to one output job.
protocol ScreenCaptureOutputEncoding: Sendable {
    func encode(_ image: CapturedScreenImage) async throws -> EncodedScreenCapture
}

/// General pasteboard boundary; receives complete representations before mutation.
@MainActor
protocol ScreenCaptureClipboardDelivering: AnyObject {
    func writeCompleteRepresentations(_ representations: EncodedScreenCapture) throws
}

/// Explicitly activates Crispy before an activating capture surface is keyed.
@MainActor
protocol ScreenCaptureApplicationActivating: AnyObject {
    func activateApplication()
}

/// Injectable AppKit window operations used to verify activation, keying, and focus order.
@MainActor
protocol ScreenCaptureWindowFocusing: AnyObject {
    func makeKeyAndOrderFront(_ window: NSWindow)
    func orderFrontRegardless(_ window: NSWindow)
    @discardableResult
    func makeFirstResponder(_ responder: NSResponder, in window: NSWindow) -> Bool
}

/// Ephemeral origin capability used only for cancellation/failure restoration.
@MainActor
final class OriginFocusContext {
    let application: NSRunningApplication
    weak var keyWindow: NSWindow?
    weak var firstResponder: NSResponder?
    private let terminationProvider: () -> Bool

    init(
        application: NSRunningApplication,
        keyWindow: NSWindow?,
        firstResponder: NSResponder?,
        terminationProvider: (() -> Bool)? = nil
    ) {
        self.application = application
        self.keyWindow = keyWindow
        self.firstResponder = firstResponder
        self.terminationProvider = terminationProvider ?? { [weak application] in application?.isTerminated ?? true }
    }

    var isTerminated: Bool { terminationProvider() }
    var processIdentifier: pid_t { application.processIdentifier }
}

/// Best-effort activation/focus boundary without input synthesis or Accessibility APIs.
@MainActor
protocol OriginFocusTracking: AnyObject {
    func captureOrigin() -> OriginFocusContext?
    func restoreIfNeeded(_ context: OriginFocusContext)
}

/// Injected multi-display selection surface owned by the next UI stage.
@MainActor
protocol ScreenCaptureSelectionControlling: AnyObject {
    func selectTarget(
        from catalog: ScreenCaptureCatalog,
        initialMode: CaptureMode,
        options: CaptureOptions,
        sessionGeneration: UInt64
    ) async throws -> CaptureSelectionDescriptor?
    func dismissSelection()
    func shutdown()
}

/// Unified successful-acquisition route. Implementations install, present/focus, then deliver.
@MainActor
protocol ScreenCaptureStudioRouting: AnyObject {
    func present(_ capture: AcquiredScreenCapture)
    func shutdown()
}

/// Recovery presentation boundary owned by the presentation layer.
@MainActor
protocol ScreenCaptureRecoveryPresenting: AnyObject {
    func presentPermission(
        _ state: ScreenCaptureAuthorizationState,
        recheck: @escaping () -> Void,
        relaunch: @escaping () -> Void,
        cancel: @escaping () -> Void
    )
    func presentError(_ error: ScreenCaptureError, perform: @escaping (ScreenCaptureRecoveryAction) -> Void)
    func dismiss()
}
