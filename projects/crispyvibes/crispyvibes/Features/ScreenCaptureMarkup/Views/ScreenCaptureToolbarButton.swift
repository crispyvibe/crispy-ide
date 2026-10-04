import SwiftUI

/// Starts the single Screenshot Studio capture workflow from the app toolbar.
@MainActor
struct ScreenCaptureToolbarButton: View {
    @ObservedObject var coordinator: ScreenCaptureCoordinator

    var isEnabled: Bool { coordinator.canBeginCapture }

    var body: some View {
        Button {
            coordinator.beginCapture()
        } label: {
            HomeToolbarIconLabel(systemName: "camera.viewfinder")
        }
        .disabled(!isEnabled)
        .help(AppStrings.ScreenCapture.captureScreenshotHelp)
        .accessibilityLabel(AppStrings.ScreenCapture.captureScreenshot)
        .accessibilityIdentifier("toolbar.capture-screenshot")
    }
}
