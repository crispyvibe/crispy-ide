import SwiftUI

@MainActor
struct RemoteTransferProgressOverlay: View {
    @Environment(\.appThemePalette) private var palette
    @ObservedObject var coordinator: RemoteTransferCoordinator

    var body: some View {
        if let operation = coordinator.operation {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: operation.mode == .download ? "arrow.down.circle" : "arrow.up.forward.app")
                        .foregroundStyle(palette.accentColor)
                    Text(operation.title)
                        .font(AppTypographyTokens.subheadlineSemibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if canCancel(operation.state) {
                        Button(AppStrings.Common.cancel, action: coordinator.cancel)
                            .buttonStyle(.borderless)
                    }
                }

                switch operation.state {
                case .preparing:
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text(AppStrings.RemoteTransfer.preparing)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                case .transferring:
                    if let fraction = operation.fractionCompleted {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    HStack {
                        Text(progressSummary(operation))
                        Spacer(minLength: 8)
                        if let currentItem = operation.currentItem {
                            Text(currentItem)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                case .cancelling:
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text(AppStrings.RemoteTransfer.cancelling)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                case .publishing:
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text(AppStrings.RemoteTransfer.publishing)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                case .completed:
                    Text(
                        operation.mode == .externalOpen
                            ? AppStrings.RemoteTransfer.temporaryCopyNotice
                            : AppStrings.RemoteTransfer.downloadComplete
                    )
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                    HStack {
                        Spacer()
                        Button(AppStrings.RemoteTransfer.showInFinder) {
                            coordinator.showCompletedItemInFinder()
                        }
                        Button(AppStrings.Common.done) {
                            coordinator.dismissCompleted()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .failed(let message):
                    Text(message)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(palette.errorColor)
                    HStack {
                        Spacer()
                        Button(AppStrings.Common.done) {
                            coordinator.dismissCompleted()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(14)
            .frame(width: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.borderColorValue.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
            .padding(18)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("remote.transfer.progress")
        }
    }

    private func canCancel(_ state: RemoteTransferCoordinator.Operation.State) -> Bool {
        switch state {
        case .preparing, .transferring:
            return true
        case .cancelling, .publishing, .completed, .failed:
            return false
        }
    }

    private func progressSummary(_ operation: RemoteTransferCoordinator.Operation) -> String {
        if operation.totalFiles > 0 {
            return AppStrings.RemoteTransfer.fileProgress(
                completed: operation.completedFiles,
                total: operation.totalFiles
            )
        }
        return AppStrings.RemoteTransfer.transferring
    }
}
