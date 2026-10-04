import AppKit
import SwiftUI

/// Unified memory-backed markup, delivery, history, and lifecycle surface for F062.
@MainActor
struct ScreenshotStudioView: View {
    @ObservedObject var viewModel: ScreenshotStudioViewModel
    let onCanvasReady: (NSResponder) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            editor
            if let failure = viewModel.failure {
                failureBanner(failure)
            }
            Divider()
            ScreenshotHistoryRail(viewModel: viewModel)
            Divider()
            actionBar
        }
        .onAppear { viewModel.refreshHistory() }
        .confirmationDialog(
            AppStrings.ScreenCapture.studioClearConfirmationTitle,
            isPresented: Binding(
                get: { viewModel.isClearConfirmationPresented },
                set: { if !$0 { viewModel.cancelClearHistory() } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.ScreenCapture.studioClearHistory, role: .destructive) {
                viewModel.confirmClearHistory()
            }
            Button(AppStrings.ScreenCapture.studioCancel, role: .cancel) {
                viewModel.cancelClearHistory()
            }
        }
        .accessibilityIdentifier("screenCapture.studio.window")
    }

    @ViewBuilder
    private var editor: some View {
        if let item = viewModel.currentItem {
            RasterImageMemoryPreviewHost(
                image: item.image,
                canvasSize: item.canvasSize,
                onRevisionChange: { session, revision, isDirty in
                    viewModel.didChangeRevision(
                        itemID: item.id,
                        session: session,
                        revision: revision,
                        isDirty: isDirty
                    )
                },
                onCanvasReady: onCanvasReady,
                viewModel: viewModel.rasterViewModel
            )
            .id(item.id)
        } else {
            ContentUnavailableView(
                AppStrings.ScreenCapture.studioNoCapture,
                systemImage: "rectangle.dashed",
                description: Text(AppStrings.ScreenCapture.studioNoCaptureDescription)
            )
            .accessibilityIdentifier("screenCapture.studio.empty")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(AppStrings.ScreenCapture.studioCopy) { viewModel.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .buttonStyle(.bordered)
                .disabled(!viewModel.canCopy)
                .accessibilityIdentifier("screenCapture.studio.copy")
            Button(AppStrings.ScreenCapture.studioCopyAndDismiss) {
                viewModel.copyAndDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canCopyAndDismiss)
            .accessibilityIdentifier("screenCapture.studio.copyAndDismiss")
            Button(AppStrings.ScreenCapture.studioDeleteCurrent, role: .destructive) {
                viewModel.deleteCurrent()
            }
            .disabled(!viewModel.canDeleteCurrent || viewModel.isCopyAndDismissPending)
            .accessibilityIdentifier("screenCapture.studio.deleteCurrent")
            Button(AppStrings.ScreenCapture.studioClearHistory, role: .destructive) {
                viewModel.requestClearHistory()
            }
            .disabled(viewModel.historyEntries.isEmpty || viewModel.isCopyAndDismissPending)
            .accessibilityIdentifier("screenCapture.studio.clearHistory")
            Spacer()
            if viewModel.isWorking || viewModel.isLoadingHistory || viewModel.isCopyAndDismissPending {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("screenCapture.studio.progress")
            }
            Button(AppStrings.ScreenCapture.studioClose) { viewModel.close() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("screenCapture.studio.close")
        }
        .padding(10)
    }

    private func failureBanner(_ failure: ScreenshotStudioFailure) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(AppStrings.ScreenCapture.studioFailureMessage(failure))
                .font(.caption.weight(contrast == .increased ? .semibold : .regular))
            Spacer()
            Button(failure.stage.supportsCopyRetry ? AppStrings.ScreenCapture.studioRetryCopy : AppStrings.ScreenCapture.studioRefresh) {
                viewModel.retryLastFailure()
            }
            .controlSize(.small)
            .accessibilityIdentifier("screenCapture.studio.retry")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screenCapture.studio.failure")
    }
}
