import CoreGraphics
import ScreenCaptureKit
import XCTest
@testable import CrispyVibes

/// F062 capture geometry, TCC, and protected-content mapping coverage.
@MainActor
final class ScreenCaptureFoundationStateTests: XCTestCase {
    private final class HistoryStore: ScreenCaptureAuthorizationHistoryStoring {
        var history: ScreenCaptureAuthorizationHistory = .neverRequested
    }

    func test_F062_S05_spanningWindowUsesDesktopIndependentTargetWithoutDisplayClipping() {
        let contentRect = CGRect(x: -320, y: 40, width: 1_600, height: 900)
        let target = ScreenCaptureStillTargetPolicy.window(
            windowID: 73,
            contentRect: contentRect,
            pointPixelScale: 2
        )

        XCTAssertEqual(target.source, .desktopIndependentWindow(windowID: 73))
        XCTAssertEqual(target.canvasSize, contentRect.size)
        XCTAssertEqual(target.outputPixelSize, CGSize(width: 3_200, height: 1_800))
        XCTAssertEqual(target.exportScale, 2)
    }

    func test_F062_S06_displayTargetUsesFullNativeBackingDimensions() {
        let display = ScreenCaptureDisplayDescriptor(
            id: 91,
            appKitFrame: CGRect(x: 1_440, y: 0, width: 1_728, height: 1_117),
            captureKitFrame: CGRect(x: 1_440, y: 0, width: 1_728, height: 1_117),
            visibleAppKitFrame: CGRect(x: 1_440, y: 24, width: 1_728, height: 1_093),
            backingScale: 2,
            nativePixelSize: CGSize(width: 3_456, height: 2_234)
        )
        let target = ScreenCaptureStillTargetPolicy.display(display)

        XCTAssertEqual(target.source, .display(displayID: 91))
        XCTAssertEqual(target.outputPixelSize, display.nativePixelSize)
        XCTAssertEqual(target.canvasSize, display.appKitFrame.size)
        XCTAssertEqual(target.exportScale, display.backingScale)
    }

    func test_neverRequestedIsUndeterminedAndRequestCanRequireRelaunch() {
        let history = HistoryStore()
        var preflight = false
        let authorizer = ScreenCaptureTCCAuthorizer(
            historyStore: history,
            preflightAccess: { preflight },
            requestAccess: { true },
            openSettings: { _ in }
        )
        XCTAssertEqual(authorizer.authorizationStatus(), .undetermined)
        XCTAssertEqual(authorizer.requestAuthorization(), .grantedRelaunchRequired)
        XCTAssertEqual(history.history, .grantedPendingRelaunch)
        preflight = true
        XCTAssertEqual(authorizer.authorizationStatus(), .granted)
        XCTAssertEqual(history.history, .previouslyGranted)
    }

    func test_previouslyGrantedThenFailedPreflightIsRevoked() {
        let history = HistoryStore()
        history.history = .previouslyGranted
        let authorizer = ScreenCaptureTCCAuthorizer(
            historyStore: history,
            preflightAccess: { false },
            requestAccess: { false },
            openSettings: { _ in }
        )
        XCTAssertEqual(authorizer.authorizationStatus(), .revoked)
        XCTAssertEqual(authorizer.requestAuthorization(), .deniedOrRestricted)
    }

    func test_screenCaptureKitErrorsMapToProtectedOrUnavailableWithoutPixelScanning() {
        let protected = NSError(domain: SCStreamErrorDomain, code: -3808)
        XCTAssertEqual(
            ScreenCaptureKitStillProvider.mapCaptureFailure(protected),
            .protectedOrUnavailableContent
        )
        let nested = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: protected]
        )
        XCTAssertEqual(
            ScreenCaptureKitStillProvider.mapCaptureFailure(nested),
            .protectedOrUnavailableContent
        )
        XCTAssertEqual(
            ScreenCaptureKitStillProvider.mapCaptureFailure(
                NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
            ),
            .captureFailed
        )
    }

    private func makeDisplay(scale: CGFloat) -> ScreenCaptureDisplayDescriptor {
        ScreenCaptureDisplayDescriptor(
            id: 44,
            appKitFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            captureKitFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleAppKitFrame: CGRect(x: 0, y: 0, width: 1_000, height: 760),
            backingScale: scale,
            nativePixelSize: CGSize(width: 1_000 * scale, height: 800 * scale)
        )
    }
}


extension ScreenCaptureFoundationStateTests {
    func test_regionEdgeLabelsUseLocalizedTypedNames() {
        XCTAssertEqual(AppStrings.ScreenCapture.regionEdge(.left), "Region edge: Left")
        XCTAssertEqual(AppStrings.ScreenCapture.regionEdge(.top), "Region edge: Top")
        XCTAssertEqual(AppStrings.ScreenCapture.regionEdge(.right), "Region edge: Right")
        XCTAssertEqual(AppStrings.ScreenCapture.regionEdge(.bottom), "Region edge: Bottom")
    }
}
