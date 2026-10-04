import Combine
import Foundation

/// Main F062 workflow coordinator. Successful acquisitions have one Screenshot Studio route.
@MainActor
final class ScreenCaptureCoordinator: ObservableObject {
    @Published private(set) var state: ScreenCaptureCoordinatorState = .idle

    let authorizer: any ScreenCaptureAuthorizing
    let provider: any ScreenCaptureProviding
    let preferences: any ScreenCapturePreferencesProviding
    let selectionController: any ScreenCaptureSelectionControlling
    let exclusionProvider: any ScreenCaptureUIExclusionProviding
    let studioRouter: any ScreenCaptureStudioRouting
    let originTracker: any OriginFocusTracking

    var sessionGeneration: UInt64 = 0
    var captureTask: Task<Void, Never>?
    var captureTaskID: UUID?
    var origin: OriginFocusContext?
    var isShutDown = false

    init(
        authorizer: any ScreenCaptureAuthorizing,
        provider: any ScreenCaptureProviding,
        preferences: any ScreenCapturePreferencesProviding,
        selectionController: any ScreenCaptureSelectionControlling,
        exclusionProvider: any ScreenCaptureUIExclusionProviding,
        studioRouter: any ScreenCaptureStudioRouting,
        originTracker: any OriginFocusTracking
    ) {
        self.authorizer = authorizer
        self.provider = provider
        self.preferences = preferences
        self.selectionController = selectionController
        self.exclusionProvider = exclusionProvider
        self.studioRouter = studioRouter
        self.originTracker = originTracker
    }

    var canBeginCapture: Bool { !isShutDown && captureTask == nil }

    /// Begins visible target selection. Shortcut bursts are coalesced while one session is active.
    func beginCapture() {
        guard canBeginCapture else { return }
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let taskID = UUID()
        origin = originTracker.captureOrigin()
        captureTaskID = taskID
        captureTask = Task { [weak self] in
            guard let self else { return }
            await self.run(generation: generation)
            self.finishSession(generation: generation, taskID: taskID)
        }
    }

    /// Cancels selection and invalidates every pending completion for the current session.
    func cancelCapture() {
        guard !isShutDown else { return }
        sessionGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        captureTaskID = nil
        selectionController.dismissSelection()
        restoreAndClearOrigin()
        state = .idle
    }

    /// Cancels acquisition and closes all injected F062 surfaces and lifecycle owners.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        sessionGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        captureTaskID = nil
        selectionController.shutdown()
        studioRouter.shutdown()
        origin = nil
        state = .shutDown
    }

    func transition(to state: ScreenCaptureCoordinatorState) {
        self.state = state
    }

    func checkCurrent(_ generation: UInt64) throws {
        guard !isShutDown, generation == sessionGeneration, !Task.isCancelled else {
            throw ScreenCaptureError.staleOperation
        }
    }

    func handleFailure(_ error: ScreenCaptureError, generation: UInt64) {
        guard !isShutDown, generation == sessionGeneration else { return }
        selectionController.dismissSelection()
        restoreAndClearOrigin()
        state = error == .cancelled ? .idle : .failed(session: generation, error: error)
    }

    func restoreAndClearOrigin() {
        if let origin { originTracker.restoreIfNeeded(origin) }
        origin = nil
    }

    func finishSession(generation: UInt64, taskID: UUID) {
        guard generation == sessionGeneration, captureTaskID == taskID else { return }
        captureTask = nil
        captureTaskID = nil
    }
}
