import AppKit
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
        func registration(for command: GlobalCaptureShortcutCommand) -> GlobalCaptureShortcutRegistration {
            .disabled
        }
        func rebind(
            _ command: GlobalCaptureShortcutCommand,
            to shortcut: GlobalCaptureShortcut?
        ) -> GlobalCaptureShortcutRegistration {
            .disabled
        }
        func unregister(_ command: GlobalCaptureShortcutCommand) {}
        func shutdown() {}
    }

    private final class RecoveryPresenter: ScreenCaptureRecoveryPresenting {
        private(set) var events: [String] = []
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
        func selectTarget(
            from catalog: ScreenCaptureCatalog,
            initialMode: CaptureMode,
            options: CaptureOptions,
            sessionGeneration: UInt64
        ) async throws -> CaptureSelectionDescriptor? {
            isCancelled ? nil : selection
        }
        func dismissSelection() {}
        func shutdown() {}
    }

    private final class Exclusion: ScreenCaptureUIExclusionProviding {
        var excludedCaptureWindowIDs: Set<CGWindowID> = []
        func prepareForCapture() async {}
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

    private struct Fixture {
        let coordinator: ScreenCaptureCoordinator
        let authorizer: Authorizer
        let provider: Provider
        let preferences: Preferences
        let selection: Selection
        let studio: StudioRouter
        let origin: Origin
    }

    private func makeServices(
        fixture: Fixture,
        recovery: RecoveryPresenter
    ) throws -> (ScreenCaptureServices, UserDefaults, String) {
        let suiteName = "ScreenCaptureCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let historyStore = ScreenCaptureHistoryStore(repository: try ControlledRepository())
        let shortcutManager = ShortcutManager()
        let settingsViewModel = ScreenCaptureSettingsViewModel(
            preferenceStore: fixture.preferences,
            authorizer: fixture.authorizer,
            registrationProvider: { .disabled },
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
            shortcutResolver: { _ in nil },
            relaunchApplication: {},
            userDefaults: defaults
        )
        return (services, defaults, suiteName)
    }

    private func makeFixture() throws -> Fixture {
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
        let coordinator = ScreenCaptureCoordinator(
            authorizer: authorizer,
            provider: provider,
            preferences: preferences,
            selectionController: selection,
            exclusionProvider: Exclusion(),
            studioRouter: studio,
            originTracker: origin
        )
        return Fixture(
            coordinator: coordinator,
            authorizer: authorizer,
            provider: provider,
            preferences: preferences,
            selection: selection,
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
