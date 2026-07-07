import SwiftUI

// F059 — the lane catalog list: browse reusable lanes, open one to edit, or
// create a new one. Split out of VibeLaneSurfaceView.swift for file size /
// one-primary-type-per-file (coding-guidelines).

@MainActor
struct VibeLaneLanesView: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.appThemePalette) private var palette
    @ObservedObject var manager: VibeLaneTaskManager
    let onEdit: (UUID) -> Void
    let onNew: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
                HStack(spacing: uiScale.spacing(12)) {
                    VibeLaneIconBadge(systemImage: "rectangle.stack", side: 36, iconSize: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppStrings.VibeLanes.yourLanes)
                            .font(.system(size: uiScale.textSize(18), weight: .bold))
                        Text("\(manager.lanes.count)")
                            .font(.system(size: uiScale.textSize(11), weight: .medium))
                            .foregroundStyle(palette.tertiaryTextColor)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button(action: { manager.restoreStarterLanes() }) {
                        Label(AppStrings.VibeLanes.restoreStarterLanes, systemImage: "arrow.counterclockwise")
                            .font(.system(size: uiScale.textSize(13)))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help(AppStrings.VibeLanes.restoreStarterLanesHelp)
                    Button(action: onNew) {
                        Label(AppStrings.VibeLanes.newLane, systemImage: "plus")
                            .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                VStack(spacing: 0) {
                    ForEach(Array(manager.lanes.enumerated()), id: \.element.id) { index, lane in
                        laneRow(lane)
                        if index < manager.lanes.count - 1 {
                            Divider().padding(.leading, uiScale.chromeSize(56))
                        }
                    }
                }
                .padding(uiScale.spacing(4))
                .vibeLaneCard()
            }
            .padding(uiScale.spacing(24))
        }
        .background(palette.canvasBackgroundColor)
    }

    private func laneRow(_ lane: VibeLaneDefinition) -> some View {
        Button { onEdit(lane.id) } label: {
            HStack(spacing: uiScale.spacing(12)) {
                VibeLaneIconBadge(systemImage: "rectangle.stack", side: 32, iconSize: 13)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: uiScale.spacing(8)) {
                        Text(lane.name)
                            .font(.system(size: uiScale.textSize(14), weight: .semibold))
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                        Text(AppStrings.VibeLanes.stepCount(lane.checkpoints.count))
                            .font(.system(size: uiScale.textSize(10), weight: .semibold))
                            .foregroundStyle(palette.secondaryTextColor)
                            .padding(.horizontal, uiScale.spacing(6))
                            .padding(.vertical, uiScale.spacing(2))
                            .background(Capsule().fill(palette.tertiaryTextColor.opacity(0.13)))
                    }
                    Text(lane.detail ?? AppStrings.VibeLanes.noLaneDetail)
                        .font(.system(size: uiScale.textSize(12)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                    Text(lane.routeSummary)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.tertiaryTextColor)
                        .lineLimit(1)
                }

                Spacer(minLength: uiScale.spacing(12))

                Image(systemName: "chevron.right")
                    .font(.system(size: uiScale.iconSize(10), weight: .semibold))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .padding(.horizontal, uiScale.spacing(14))
            .padding(.vertical, uiScale.spacing(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vibeLaneHoverable()
    }
}
