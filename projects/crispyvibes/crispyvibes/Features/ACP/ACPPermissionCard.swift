import SwiftUI

struct ACPPermissionCard: View {
    @Environment(\.appThemePalette) private var palette
    let request: ACPPermissionHandler.PendingRequest
    let onDecision: (ACPPermissionOutcome) -> Void
    /// Called when user chooses "Accept for Session" — auto-approves all future requests.
    var onAcceptForSession: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(AppTypographyTokens.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Required")
                        .font(AppTypographyTokens.subheadlineSemibold)
                    Text(request.toolCallTitle)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                }
                Spacer()
            }

            // Diffs
            if !request.diffs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(request.diffs.enumerated()), id: \.offset) { _, diff in
                        ACPDiffView(
                            diff: diff,
                            onLinkTargetActivated: nil,
                            onFileSystemTargetActivated: nil
                        )
                    }
                }
            }

            // Actions
            HStack(spacing: 8) {
                Button("Cancel") { onDecision(.cancelled) }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondaryTextColor)

                Spacer()

                // Accept for Session — auto-approves all future requests (#22)
                if let onAcceptForSession, request.options.contains(where: { $0.kind.contains("allow") }) {
                    Button {
                        onAcceptForSession()
                        if let allowOption = request.options.first(where: { $0.kind.contains("allow") }) {
                            onDecision(.selected(optionId: allowOption.optionId))
                        }
                    } label: {
                        Text("Accept for Session").font(AppTypographyTokens.captionSemibold)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach(request.options, id: \.optionId) { option in
                    permissionButton(option)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    @ViewBuilder
    private func permissionButton(_ option: ACPPermissionOption) -> some View {
        if option.kind.contains("allow") {
            Button {
                onDecision(.selected(optionId: option.optionId))
            } label: {
                Text(option.name).font(AppTypographyTokens.captionSemibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button {
                onDecision(.selected(optionId: option.optionId))
            } label: {
                Text(option.name).font(AppTypographyTokens.captionSemibold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
