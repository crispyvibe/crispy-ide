import AppKit
import Carbon
import Combine
import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F062 unified acquisition-to-Studio workflow tests with injected doubles.
@MainActor
final class ScreenCaptureCoordinatorTests: XCTestCase {
    private final class Authorizer: ScreenCaptureAuthorizing {
        var state: ScreenCaptureAuthorizationState = .granted
        var cachedAuthorizationState: ScreenCaptureAuthorizationState { state }
        private(set) var statusCalls = 0
        func authorizationStatus() -> ScreenCaptureAuthorizationState {
            statusCalls += 1
            return state
        }
        func requestAuthorization() -> ScreenCaptureAuthorizationState { state }
        func openScreenRecordingSettings() {}
    }

    private actor Provider: ScreenCaptureProviding {
        let catalogValue: ScreenCaptureCatalog
        let image: CapturedScreenImage
        private(set) var captureCount = 0
        private(set) var catalogCount = 0
        var failure: ScreenCaptureError?

        init(catalog: ScreenCaptureCatalog, image: CapturedScreenImage) {
            catalogValue = catalog
            self.image = image
        }

        func catalog() async throws -> ScreenCaptureCatalog {
            catalogCount += 1
            return catalogValue
        }

        func capture(
            selection: CaptureSelectionDescriptor,
            excludingWindowIDs: Set<CGWindowID>
        ) async throws -> CapturedScreenImage {
            captureCount += 1
            if let failure { throw failure }
            return image
        }

        func setFailure(_ error: ScreenCaptureError?) { failure = error }
        func counts() -> (catalog: Int, capture: Int) { (catalogCount, captureCount) }
    }

    private final class Preferences: ScreenCapturePreferencesManaging {
        private let subject = CurrentValueSubject<ScreenCapturePreferences, Never>(.default)
        var screenCapturePreferences: ScreenCapturePreferences { subject.value }
        var screenCapturePreferencesPublisher: AnyPublisher<ScreenCapturePreferences, Never> {
            subject.eraseToAnyPublisher()
        }
        private(set) var updatedMode: CaptureMode?
        func updateRememberedMode(_ mode: CaptureMode) {
            updatedMode = mode
            subject.send(.init(mode: mode, options: subject.value.options))
        }
        func updateDelay(_ delay: CaptureDelay) {
            subject.send(.init(
                mode: subject.value.mode,
                options: .init(delay: delay, includesPointer: subject.value.options.includesPointer)
            ))
        }
        func updateIncludesPointer(_ includesPointer: Bool) {
            subject.send(.init(
                mode: subject.value.mode,
                options: .init(delay: subject.value.options.delay, includesPointer: includesPointer)
            ))
        }
        func reset() { subject.send(.default) }
    }

    private final class ShortcutManager: GlobalCaptureShortcutManaging {
        var onRegistrationChanged: (() -> Void)?
        var registrationState: GlobalCaptureShortcutRegistration = .disabled
        var nextRebindResult: GlobalCaptureShortcutRegistration?
        private(set) var rebindCalls: [GlobalCaptureShortcut?] = []
        private(set) var shutdownCount = 0

        func registration(for command: GlobalCaptureShortcutCommand) -> GlobalCaptureShortcutRegistration {
            registrationState
        }

        func rebind(
            _ command: GlobalCaptureShortcutCommand,
            to shortcut: GlobalCaptureShortcut?
        ) -> GlobalCaptureShortcutRegistration {
            rebindCalls.append(shortcut)
            let result = nextRebindResult ?? shortcut.map(GlobalCaptureShortcutRegistration.registered) ?? .disabled
            nextRebindResult = nil
            registrationState = result
            return result
        }

        func unregister(_ command: GlobalCaptureShortcutCommand) {
            registrationState = .disabled
        }

        func shutdown() {
            shutdownCount += 1
            registrationState = .disabled
        }
    }

    private final class RecoveryPresenter: ScreenCaptureRecoveryPresenting {
        private(set) var events: [String] = []
        private(set) var presentedError: ScreenCaptureError?
        private(set) var isPresented = false
        private var recheck: (() -> Void)?
        private var cancel: (() -> Void)?

        func presentPermission(
            _ state: ScreenCaptureAuthorizationState,
            recheck: @escaping () -> Void,
            relaunch: @escaping () -> Void,
            cancel: @escaping () -> Void
        ) {
            events.append("presentPermission")
            isPresented = true
            self.recheck = recheck
            self.cancel = cancel
        }

        func presentError(
            _ error: ScreenCaptureError,
            perform: @escaping (ScreenCaptureRecoveryAction) -> Void
        ) {
            events.append("presentError")
            presentedError = error
            isPresented = true
        }

        func dismiss() {
            events.append("dismiss")
            isPresented = false
        }

        func performRecheck() { recheck?() }
        func performCancel() { cancel?() }
    }

    private final class Selection: ScreenCaptureSelectionControlling {
        var selection: CaptureSelectionDescriptor?
        var isCancelled = false
        private(set) var selectCount = 0
        func selectTarget(
            from catalog: ScreenCaptureCatalog,
            initialMode: CaptureMode,
            options: CaptureOptions,
            sessionGeneration: UInt64
        ) async throws -> CaptureSelectionDescriptor? {
            selectCount += 1
            return isCancelled ? nil : selection
        }
        func dismissSelection() {}
        func shutdown() {}
    }

    private final class HiddenSurfaceToken: ScreenCaptureHiddenSurfaceRestoring {
        private(set) var restoreCount = 0
        func restore() { restoreCount += 1 }
    }

    private final class Exclusion: ScreenCaptureUIExclusionProviding {
        var excludedCaptureWindowIDs: Set<CGWindowID> = []
        let token = HiddenSurfaceToken()
        func prepareForCapture() async -> any ScreenCaptureHiddenSurfaceRestoring { token }
    }

    private final class StudioRouter: ScreenCaptureStudioRouting {
        private(set) var captures: [AcquiredScreenCapture] = []
        private(set) var shutdownCount = 0
        func present(_ capture: AcquiredScreenCapture) { captures.append(capture) }
        func shutdown() { shutdownCount += 1 }
    }

    private final class Origin: OriginFocusTracking {
        var context: OriginFocusContext?
        private(set) var restoreCount = 0
        func captureOrigin() -> OriginFocusContext? { context }
        func restoreIfNeeded(_ context: OriginFocusContext) { restoreCount += 1 }
    }

    func test_successRoutesExactlyOnceToStudioAndPersistsCommittedMode() async throws {
        let fixture = try makeFixture()
        fixture.coordinator.beginCapture()
        try await waitUntil { fixture.studio.captures.count == 1 }

        XCTAssertEqual(fixture.preferences.updatedMode, .display)
        let successCounts = await fixture.provider.counts()
        XCTAssertEqual(successCounts.capture, 1)
        XCTAssertTrue(fixture.coordinator.canBeginCapture)
        guard case .presentingStudio(let id) = fixture.coordinator.state else {
            return XCTFail("Expected the unified Studio route")
        }
        XCTAssertEqual(id, fixture.studio.captures[0].id)
    }

    func test_cancelledSelectionRestoresOriginAndDoesNotPresentStudio() async throws {
        let fixture = try makeFixture()
        fixture.origin.context = OriginFocusContext(
            application: .current,
            keyWindow: nil,
            firstResponder: nil
        )
        fixture.selection.isCancelled = true

        fixture.coordinator.beginCapture()
        try await waitUntil { fixture.coordinator.canBeginCapture }

        XCTAssertEqual(fixture.origin.restoreCount, 1)
        XCTAssertTrue(fixture.studio.captures.isEmpty)
        guard case .idle = fixture.coordinator.state else { return XCTFail("Expected idle") }
    }

    func test_captureFailureRestoresOriginAndRetainsNoRouteState() async throws {
        let fixture = try makeFixture()
        fixture.origin.context = OriginFocusContext(
            application: .current,
            keyWindow: nil,
            firstResponder: nil
        )
        await fixture.provider.setFailure(.captureFailed)

        fixture.coordinator.beginCapture()
        try await waitUntil {
            if case .failed = fixture.coordinator.state { return true }
            return false
        }

        XCTAssertEqual(fixture.origin.restoreCount, 1)
        XCTAssertTrue(fixture.studio.captures.isEmpty)
    }

    func test_permissionFailureRestoresOriginWithoutCatalogOrStudio() async throws {
        let fixture = try makeFixture()
        fixture.origin.context = OriginFocusContext(
            application: .current,
            keyWindow: nil,
            firstResponder: nil
        )
        fixture.authorizer.state = .deniedOrRestricted

        fixture.coordinator.beginCapture()
        try await waitUntil {
            if case .permissionRequired = fixture.coordinator.state { return true }
            return false
        }

        XCTAssertEqual(fixture.origin.restoreCount, 1)
        let permissionCounts = await fixture.provider.counts()
        XCTAssertEqual(permissionCounts.catalog, 0)
        XCTAssertTrue(fixture.studio.captures.isEmpty)
    }

    func test_permissionRecoveryRecheckDismissesOnceBeforeStartingCapture() async throws {
        let fixture = try makeFixture()
        fixture.authorizer.state = .deniedOrRestricted
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(fixture: fixture, recovery: recovery)
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }
        services.start()
        fixture.coordinator.beginCapture()
        try await waitUntil {
            recovery.isPresented && fixture.coordinator.canBeginCapture
        }

        fixture.authorizer.state = .granted
        recovery.performRecheck()

        XCTAssertEqual(recovery.events, ["presentPermission", "dismiss"])
        XCTAssertFalse(recovery.isPresented)
        try await waitUntil { fixture.studio.captures.count == 1 }
        XCTAssertFalse(recovery.isPresented, "Recovery must not coexist with Screenshot Studio")
        XCTAssertEqual(fixture.authorizer.statusCalls, 2)
    }

    func test_permissionRecoveryCancelDismissesOnceAndReturnsCoordinatorToIdle() async throws {
        let fixture = try makeFixture()
        fixture.authorizer.state = .deniedOrRestricted
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(fixture: fixture, recovery: recovery)
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }
        services.start()
        fixture.coordinator.beginCapture()
        try await waitUntil {
            recovery.isPresented && fixture.coordinator.canBeginCapture
        }

        recovery.performCancel()

        XCTAssertEqual(recovery.events, ["presentPermission", "dismiss"])
        XCTAssertFalse(recovery.isPresented)
        XCTAssertEqual(fixture.authorizer.statusCalls, 1)
        XCTAssertTrue(fixture.studio.captures.isEmpty)
        guard case .idle = fixture.coordinator.state else {
            return XCTFail("Expected Cancel to return the coordinator to idle")
        }
    }

    func test_nonPermissionCoordinatorStateDismissesStalePermissionRecoveryOnce() async throws {
        let fixture = try makeFixture()
        fixture.authorizer.state = .deniedOrRestricted
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(fixture: fixture, recovery: recovery)
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }
        services.start()
        fixture.coordinator.beginCapture()
        try await waitUntil {
            recovery.isPresented && fixture.coordinator.canBeginCapture
        }

        fixture.coordinator.transition(to: .selecting(
            session: 2,
            mode: .region,
            topologyGeneration: 3
        ))

        XCTAssertEqual(recovery.events, ["presentPermission", "dismiss"])
        XCTAssertFalse(recovery.isPresented, "Recovery must not coexist with selection")
    }

    func test_secondStartRegistersAfterInitialRegistrationFailure() throws {
        let fixture = try makeFixture()
        let manager = ShortcutManager()
        let expected = GlobalCaptureShortcut(
            keyCode: UInt32(AppShortcutKeyCode.four),
            modifiers: UInt32(controlKey | shiftKey)
        )
        manager.nextRebindResult = .failed(expected)
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(
            fixture: fixture,
            recovery: recovery,
            shortcutManager: manager,
            shortcutResolver: { _ in expected }
        )
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }

        services.start()
        services.start()

        XCTAssertEqual(manager.rebindCalls, [expected, expected])
        XCTAssertEqual(manager.registrationState, .registered(expected))
    }

    func test_repeatedStartWithExactRegistrationDoesNotChurn() throws {
        let fixture = try makeFixture()
        let manager = ShortcutManager()
        let expected = GlobalCaptureShortcut(
            keyCode: UInt32(AppShortcutKeyCode.four),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(
            fixture: fixture,
            recovery: recovery,
            shortcutManager: manager,
            shortcutResolver: { _ in expected }
        )
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }

        services.start()
        services.start()
        services.start()

        XCTAssertEqual(manager.rebindCalls, [expected])
    }

    func test_repeatedStartReconcilesLostFailedAndMismatchedRegistrations() throws {
        let fixture = try makeFixture()
        let manager = ShortcutManager()
        let expected = GlobalCaptureShortcut(
            keyCode: UInt32(AppShortcutKeyCode.four),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(
            fixture: fixture,
            recovery: recovery,
            shortcutManager: manager,
            shortcutResolver: { _ in expected }
        )
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }

        services.start()
        manager.registrationState = .disabled
        services.start()
        manager.registrationState = .failed(expected)
        services.start()
        manager.registrationState = .registered(.init(keyCode: 20, modifiers: 0x0200))
        services.start()

        XCTAssertEqual(manager.rebindCalls, [expected, expected, expected, expected])
        XCTAssertEqual(manager.registrationState, .registered(expected))
    }

    func test_repeatedStartLeavesDisabledBindingUnregistered() throws {
        let fixture = try makeFixture()
        let manager = ShortcutManager()
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(
            fixture: fixture,
            recovery: recovery,
            shortcutManager: manager
        )
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }

        services.start()
        services.start()

        XCTAssertTrue(manager.rebindCalls.isEmpty)
        XCTAssertEqual(manager.registrationState, .disabled)
    }

    func test_bindingChangeNotificationRebindsExactlyOnce() throws {
        let fixture = try makeFixture()
        let manager = ShortcutManager()
        let first = GlobalCaptureShortcut(
            keyCode: UInt32(AppShortcutKeyCode.four),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let second = GlobalCaptureShortcut(keyCode: 20, modifiers: 0x0200)
        var configured = first
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(
            fixture: fixture,
            recovery: recovery,
            shortcutManager: manager,
            shortcutResolver: { _ in configured }
        )
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }
        services.start()

        configured = second
        NotificationCenter.default.post(name: .appShortcutBindingsDidChange, object: nil)

        XCTAssertEqual(manager.rebindCalls, [first, second])
        XCTAssertEqual(manager.registrationState, .registered(second))
    }

    func test_captureAvailabilityPublishesTrueThenFalseAndRefreshesToolbarEnablement() async throws {
        let fixture = try makeFixture()
        var published: [Bool] = []
        let observation = fixture.coordinator.$isCaptureInFlight.sink { published.append($0) }
        let toolbar = ScreenCaptureToolbarButton(coordinator: fixture.coordinator)
        XCTAssertTrue(toolbar.isEnabled)

        fixture.coordinator.beginCapture()

        XCTAssertFalse(toolbar.isEnabled)
        XCTAssertEqual(Array(published.prefix(2)), [false, true])
        try await waitUntil { fixture.coordinator.canBeginCapture }
        XCTAssertTrue(toolbar.isEnabled)
        XCTAssertEqual(published.last, false)
        withExtendedLifetime(observation) {}
    }

    func test_permissionOriginIsRestoredBeforeRecoveryStatePublishes() async throws {
        let fixture = try makeFixture()
        fixture.origin.context = OriginFocusContext(
            application: .current,
            keyWindow: nil,
            firstResponder: nil
        )
        fixture.authorizer.state = .deniedOrRestricted
        var restoreCountAtPublication: Int?
        let observation = fixture.coordinator.$state.sink { state in
            if case .permissionRequired = state {
                restoreCountAtPublication = fixture.origin.restoreCount
            }
        }

        fixture.coordinator.beginCapture()
        try await waitUntil { restoreCountAtPublication != nil }

        XCTAssertEqual(restoreCountAtPublication, 1)
        withExtendedLifetime(observation) {}
    }

    func test_acquisitionFailureRestoresPreviouslyVisibleCaptureSurfaces() async throws {
        let fixture = try makeFixture()
        await fixture.provider.setFailure(.captureFailed)

        fixture.coordinator.beginCapture()
        try await waitUntil {
            if case .failed = fixture.coordinator.state { return true }
            return false
        }

        XCTAssertEqual(fixture.exclusion.token.restoreCount, 1)
        XCTAssertTrue(fixture.coordinator.canBeginCapture)
    }

    func test_cancelAfterCompositorBarrierRestoresPreviouslyVisibleCaptureSurfaces() async throws {
        let catalog = makeCatalog()
        let provider = CancellationProvider(catalog: catalog)
        let selection = Selection()
        selection.selection = CaptureSelectionDescriptor(
            target: .display(displayID: 1),
            options: .default,
            catalogGeneration: catalog.generation,
            topology: catalog.topology
        )
        let exclusion = Exclusion()
        let coordinator = ScreenCaptureCoordinator(
            authorizer: Authorizer(),
            provider: provider,
            preferences: Preferences(),
            selectionController: selection,
            exclusionProvider: exclusion,
            studioRouter: StudioRouter(),
            originTracker: Origin()
        )
        coordinator.beginCapture()
        try await waitUntil {
            if case .capturing = coordinator.state { return true }
            return false
        }

        coordinator.cancelCapture()

        XCTAssertEqual(exclusion.token.restoreCount, 1)
        XCTAssertTrue(coordinator.canBeginCapture)
        guard case .idle = coordinator.state else { return XCTFail("Expected idle after cancel") }
    }

    func test_shutdownThenStartNeverReregistersAndPublishesFinalDisabledStatus() throws {
        let fixture = try makeFixture()
        let manager = ShortcutManager()
        let expected = GlobalCaptureShortcut(
            keyCode: UInt32(AppShortcutKeyCode.four),
            modifiers: UInt32(controlKey | shiftKey)
        )
        let (services, defaults, suiteName) = try makeServices(
            fixture: fixture,
            recovery: RecoveryPresenter(),
            shortcutManager: manager,
            shortcutResolver: { _ in expected }
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }
        services.start()
        XCTAssertEqual(manager.rebindCalls, [expected])

        services.shutdown()
        services.start()
        services.reconcileGlobalShortcut()
        NotificationCenter.default.post(name: .appShortcutBindingsDidChange, object: nil)

        XCTAssertEqual(services.lifecycleState, .shutDown)
        XCTAssertEqual(manager.rebindCalls, [expected])
        XCTAssertEqual(manager.shutdownCount, 1)
        XCTAssertEqual(services.settingsViewModel.registration, .disabled)
    }

    func test_overlayEmptyCatalogThrowsAndCoordinatorRecoversAvailability() async throws {
        let emptyCatalog = ScreenCaptureCatalog(generation: 9, displays: [], windows: [])
        let provider = Provider(catalog: emptyCatalog, image: try makeImage())
        let overlay = makeUnavailableOverlayController()
        let coordinator = ScreenCaptureCoordinator(
            authorizer: Authorizer(),
            provider: provider,
            preferences: Preferences(),
            selectionController: overlay,
            exclusionProvider: Exclusion(),
            studioRouter: StudioRouter(),
            originTracker: Origin()
        )

        coordinator.beginCapture()
        try await waitUntil { coordinator.canBeginCapture }

        guard case .failed(_, let error) = coordinator.state else {
            return XCTFail("Expected an empty-catalog failure")
        }
        XCTAssertEqual(error, .catalogUnavailable)
    }

    func test_overlayScreenMismatchThrowsTargetUnavailableWithoutSuspending() async throws {
        let catalog = makeCatalog()
        let overlay = makeUnavailableOverlayController()

        do {
            _ = try await overlay.selectTarget(
                from: catalog,
                initialMode: .region,
                options: .default,
                sessionGeneration: 1
            )
            XCTFail("Expected targetUnavailable")
        } catch let error as ScreenCaptureError {
            XCTAssertEqual(error, .targetUnavailable)
        }
    }

    func test_catalogStageTimeoutFailsWithStructuredRecoveryBeforeSelection() async throws {
        let catalog = makeCatalog()
        let provider = Provider(catalog: catalog, image: try makeImage())
        let selection = Selection()
        let coordinator = ScreenCaptureCoordinator(
            authorizer: Authorizer(),
            provider: provider,
            preferences: Preferences(),
            selectionController: selection,
            exclusionProvider: Exclusion(),
            studioRouter: StudioRouter(),
            originTracker: Origin(),
            stageRacer: CatalogTimeoutRacer()
        )

        coordinator.beginCapture()
        try await waitUntil { coordinator.canBeginCapture }

        guard case .failed(_, let error) = coordinator.state else {
            return XCTFail("Expected catalog timeout failure")
        }
        XCTAssertEqual(error, .catalogUnavailable)
        let counts = await provider.counts()
        XCTAssertEqual(counts.catalog, 0)
    }

    func test_acquisitionStageTimeoutRestoresOriginAndHiddenSurfacesPresentsRecoveryAndClearsInFlightWithoutStudioRoute() async throws {
        let racer = AcquisitionTimeoutRacer()
        let fixture = try makeFixture(stageRacer: racer)
        fixture.origin.context = OriginFocusContext(
            application: .current,
            keyWindow: nil,
            firstResponder: nil
        )
        let recovery = RecoveryPresenter()
        let (services, defaults, suiteName) = try makeServices(fixture: fixture, recovery: recovery)
        defer {
            services.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }
        services.start()

        fixture.coordinator.beginCapture()
        try await waitUntil {
            fixture.coordinator.canBeginCapture && recovery.isPresented
        }

        guard case .failed(_, let error) = fixture.coordinator.state else {
            return XCTFail("Expected acquisition timeout failure")
        }
        XCTAssertEqual(error, .captureFailed)
        XCTAssertEqual(recovery.presentedError, .captureFailed)
        XCTAssertEqual(recovery.events, ["presentError"])
        XCTAssertEqual(fixture.origin.restoreCount, 1)
        XCTAssertEqual(fixture.exclusion.token.restoreCount, 1)
        XCTAssertEqual(fixture.selection.selectCount, 1, "Interactive selection must run directly without a timeout race")
        XCTAssertFalse(fixture.coordinator.isCaptureInFlight)
        XCTAssertTrue(fixture.coordinator.canBeginCapture)
        XCTAssertTrue(fixture.studio.captures.isEmpty, "A timed-out acquisition must not reach Studio, clipboard, or history delivery")

        let providerCounts = await fixture.provider.counts()
        XCTAssertEqual(providerCounts.catalog, 1)
        XCTAssertEqual(providerCounts.capture, 0)
        let racerCounts = await racer.counts()
        XCTAssertEqual(racerCounts.catalog, 1)
        XCTAssertEqual(racerCounts.capture, 1)
    }

    func test_shutdownClosesStudioAndPreventsNewCapture() throws {
        let fixture = try makeFixture()
        fixture.coordinator.shutdown()
        fixture.coordinator.beginCapture()

        XCTAssertEqual(fixture.studio.shutdownCount, 1)
        XCTAssertFalse(fixture.coordinator.canBeginCapture)
        guard case .shutDown = fixture.coordinator.state else {
            return XCTFail("Expected shutdown")
        }
    }

    private actor CancellationProvider: ScreenCaptureProviding {
        let catalogValue: ScreenCaptureCatalog
        init(catalog: ScreenCaptureCatalog) { catalogValue = catalog }
        func catalog() async throws -> ScreenCaptureCatalog { catalogValue }
        func capture(
            selection: CaptureSelectionDescriptor,
            excludingWindowIDs: Set<CGWindowID>
        ) async throws -> CapturedScreenImage {
            try await Task.sleep(for: .seconds(60))
            throw ScreenCaptureError.cancelled
        }
    }

    private struct CatalogTimeoutRacer: ScreenCaptureStageRacing {
        func catalog(
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> ScreenCaptureCatalog
        ) async throws -> ScreenCaptureCatalog {
            throw ScreenCaptureError.catalogUnavailable
        }

        func capture(
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> CapturedScreenImage
        ) async throws -> CapturedScreenImage {
            try await operation()
        }
    }

    private actor AcquisitionTimeoutRacer: ScreenCaptureStageRacing {
        private var catalogRaceCount = 0
        private var captureRaceCount = 0

        func catalog(
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> ScreenCaptureCatalog
        ) async throws -> ScreenCaptureCatalog {
            catalogRaceCount += 1
            return try await operation()
        }

        func capture(
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> CapturedScreenImage
        ) async throws -> CapturedScreenImage {
            captureRaceCount += 1
            throw ScreenCaptureError.captureFailed
        }

        func counts() -> (catalog: Int, capture: Int) {
            (catalogRaceCount, captureRaceCount)
        }
    }

    private actor EmptyMagnifierSampler: ScreenCaptureMagnifierSampling {
        func sample(_ request: ScreenCaptureMagnifierRequest) async -> CGImage? { nil }
    }

    private func makeUnavailableOverlayController() -> ScreenCaptureOverlayController {
        ScreenCaptureOverlayController(
            surfaceRegistry: ScreenCaptureSurfaceRegistry(),
            screenResolver: { _ in nil },
            selectionViewModelFactory: { catalog, mode, options in
                CaptureSelectionViewModel(
                    catalog: catalog,
                    initialMode: mode,
                    options: options,
                    magnifierSampler: EmptyMagnifierSampler(),
                    excludedWindowIDs: { [] },
                    announce: { _ in }
                )
            }
        )
    }

    private struct Fixture {
        let coordinator: ScreenCaptureCoordinator
        let authorizer: Authorizer
        let provider: Provider
        let preferences: Preferences
        let selection: Selection
        let exclusion: Exclusion
        let studio: StudioRouter
        let origin: Origin
    }

    private func makeServices(
        fixture: Fixture,
        recovery: RecoveryPresenter,
        shortcutManager: ShortcutManager? = nil,
        shortcutResolver: @escaping (AppShortcutBinding?) -> GlobalCaptureShortcut? = { _ in nil }
    ) throws -> (ScreenCaptureServices, UserDefaults, String) {
        let shortcutManager = shortcutManager ?? ShortcutManager()
        let suiteName = "ScreenCaptureCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let historyStore = ScreenCaptureHistoryStore(repository: try ControlledRepository())
        let settingsViewModel = ScreenCaptureSettingsViewModel(
            preferenceStore: fixture.preferences,
            authorizer: fixture.authorizer,
            registrationProvider: {
                shortcutManager.registration(for: .captureScreen)
            },
            historyStore: historyStore,
            clearHistory: {}
        )
        let shortcutSettingsStore = AppShortcutSettingsStore(userDefaults: defaults)
        let services = ScreenCaptureServices(
            coordinator: fixture.coordinator,
            preferences: fixture.preferences,
            shortcutManager: shortcutManager,
            settingsViewModel: settingsViewModel,
            shortcutSettingsStore: shortcutSettingsStore,
            historyStore: historyStore,
            recoveryController: recovery,
            authorizer: fixture.authorizer,
            shortcutResolver: shortcutResolver,
            relaunchApplication: {},
            userDefaults: defaults
        )
        return (services, defaults, suiteName)
    }

    private func makeFixture(
        stageRacer: any ScreenCaptureStageRacing = ContinuousScreenCaptureStageRacer()
    ) throws -> Fixture {
        let catalog = makeCatalog()
        let provider = Provider(catalog: catalog, image: try makeImage())
        let authorizer = Authorizer()
        let preferences = Preferences()
        let selection = Selection()
        selection.selection = CaptureSelectionDescriptor(
            target: .display(displayID: 1),
            options: .default,
            catalogGeneration: catalog.generation,
            topology: catalog.topology
        )
        let studio = StudioRouter()
        let origin = Origin()
        let exclusion = Exclusion()
        let coordinator = ScreenCaptureCoordinator(
            authorizer: authorizer,
            provider: provider,
            preferences: preferences,
            selectionController: selection,
            exclusionProvider: exclusion,
            studioRouter: studio,
            originTracker: origin,
            stageRacer: stageRacer
        )
        return Fixture(
            coordinator: coordinator,
            authorizer: authorizer,
            provider: provider,
            preferences: preferences,
            selection: selection,
            exclusion: exclusion,
            studio: studio,
            origin: origin
        )
    }

    private func makeCatalog() -> ScreenCaptureCatalog {
        ScreenCaptureCatalog(generation: 2, displays: [
            ScreenCaptureDisplayDescriptor(
                id: 1,
                appKitFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                captureKitFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                visibleAppKitFrame: CGRect(x: 0, y: 0, width: 100, height: 90),
                backingScale: 1,
                nativePixelSize: CGSize(width: 100, height: 100)
            )
        ], windows: [])
    }

    private func makeImage() throws -> CapturedScreenImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return CapturedScreenImage(
            cgImage: try XCTUnwrap(context.makeImage()),
            canvasSize: CGSize(width: 2, height: 2),
            exportScale: 1,
            nativePixelSize: CGSize(width: 2, height: 2),
            colorSpaceName: nil,
            placement: .init(
                displayID: 1,
                visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 90)
            )
        )
    }

    private func waitUntil(condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for coordinator")
    }
}
