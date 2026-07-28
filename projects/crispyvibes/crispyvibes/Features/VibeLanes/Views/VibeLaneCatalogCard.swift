import SwiftUI

@MainActor
struct VibeLaneCatalogCard: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.appThemePalette) private var palette

    let lane: VibeLaneDefinition
    let categories: [VibeCategory]
    let onOpen: () -> Void
    /// Starts a task on this lane. nil hides the action (non-runnable lanes, or
    /// hosts with no task surface).
    var onStart: (() -> Void)?

    @State private var hovering = false

    private var previewCheckpoints: [VibeLaneCheckpoint] {
        let limit = lane.checkpoints.count > 4 ? 3 : 4
        return Array(lane.orderedCheckpoints.prefix(limit))
    }

    private var remainingSteps: Int {
        max(0, lane.checkpoints.count - previewCheckpoints.count)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: uiScale.spacing(13)) {
                cardHeader
                Text(lane.detail ?? AppStrings.VibeLanes.noLaneDetail)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                recipePreview
                Spacer(minLength: 0)
                categorySummary
                footer
            }
            .padding(uiScale.spacing(15))
            .frame(maxWidth: .infinity, minHeight: uiScale.chromeSize(228), alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
            .shadow(
                color: palette.borderColorValue.opacity(hovering ? 0.12 : 0.06),
                radius: uiScale.chromeSize(hovering ? 7 : 4),
                y: uiScale.chromeSize(2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .accessibilityLabel(
            "\(lane.name). \(lane.detail ?? AppStrings.VibeLanes.noLaneDetail). "
                + "\(AppStrings.VibeLanes.stepCount(lane.checkpoints.count)). "
                + "\(lane.isRunnable ? AppStrings.VibeLanes.ready : AppStrings.VibeLanes.laneNeedsSetup)"
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
            .fill(
                hovering
                    ? palette.selectionBackgroundColor.opacity(0.12)
                    : palette.canvasSecondaryBackgroundColor
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
            .strokeBorder(
                hovering
                    ? palette.warningColor.opacity(0.46)
                    : palette.borderColorValue.opacity(0.48),
                lineWidth: uiScale.chromeSize(1)
            )
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(10)) {
            VibeLaneIconBadge(
                systemImage: "point.3.connected.trianglepath.dotted",
                color: palette.warningColor,
                side: 34,
                iconSize: 13
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(2)) {
                Text(lane.name)
                    .font(.system(size: uiScale.textSize(14), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)
                Text(AppStrings.VibeLanes.vibeVersion(lane.version))
                    .font(.system(size: uiScale.textSize(9), weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            Spacer(minLength: uiScale.spacing(4))
            VibeLaneStatusChip(
                text: lane.isRunnable ? AppStrings.VibeLanes.ready : AppStrings.VibeLanes.laneNeedsSetup,
                color: lane.isRunnable ? palette.successColor : palette.warningColor,
                icon: lane.isRunnable ? "checkmark" : "exclamationmark",
                size: 9
            )
        }
    }

    private var recipePreview: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            Text(AppStrings.VibeLanes.laneRecipePreview.uppercased())
                .font(.system(size: uiScale.textSize(9), weight: .bold))
                .foregroundStyle(palette.tertiaryTextColor)

            if previewCheckpoints.isEmpty {
                Label(AppStrings.VibeLanes.noLaneSteps, systemImage: "plus.circle")
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(palette.warningColor)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(previewCheckpoints.enumerated()), id: \.offset) { index, checkpoint in
                        let loop = lane.loopGroup(containing: checkpoint.key)
                        recipeNode(index: index, checkpoint: checkpoint, loop: loop)
                        if index < previewCheckpoints.count - 1 || remainingSteps > 0 {
                            let nextLoop = index + 1 < previewCheckpoints.count
                                ? lane.loopGroup(containing: previewCheckpoints[index + 1].key)
                                : nil
                            recipeConnector(isLoop: loop != nil && loop?.key == nextLoop?.key)
                        }
                    }
                    if remainingSteps > 0 {
                        overflowNode
                    }
                }
            }
        }
    }

    private func recipeNode(
        index: Int,
        checkpoint: VibeLaneCheckpoint,
        loop: VibeLaneLoopGroup?
    ) -> some View {
        let tint = loop == nil ? palette.warningColor : palette.accentColor
        return VStack(spacing: uiScale.spacing(5)) {
            Text("\(index + 1)")
                .font(.system(size: uiScale.textSize(9), weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: uiScale.chromeSize(22), height: uiScale.chromeSize(22))
                .background(Circle().fill(tint.opacity(0.14)))
                .overlay(Circle().strokeBorder(tint.opacity(loop == nil ? 0.34 : 0.75)))
                .overlay(alignment: .topTrailing) {
                    if loop != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: uiScale.iconSize(7), weight: .bold))
                            .foregroundStyle(tint)
                            .padding(uiScale.spacing(1))
                            .background(Circle().fill(palette.canvasSecondaryBackgroundColor))
                            .offset(x: uiScale.chromeSize(4), y: uiScale.chromeSize(-3))
                    }
                }
            Text(checkpoint.displayTitle)
                .font(.system(size: uiScale.textSize(9), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let loop, loop.members.first == checkpoint.key {
                Text(AppStrings.VibeLanes.loopIterationsShort(loop.maxIterations))
                    .font(.system(size: uiScale.textSize(8), weight: .medium))
                    .foregroundStyle(palette.accentColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func recipeConnector(isLoop: Bool) -> some View {
        Group {
            if isLoop {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: uiScale.iconSize(9), weight: .bold))
                    .foregroundStyle(palette.accentColor)
                    .frame(width: uiScale.chromeSize(15))
            } else {
                Rectangle()
                    .fill(palette.warningColor.opacity(0.34))
                    .frame(width: uiScale.chromeSize(13), height: uiScale.chromeSize(1))
            }
        }
        .padding(.top, uiScale.chromeSize(11))
    }

    private var overflowNode: some View {
        VStack(spacing: uiScale.spacing(5)) {
            Image(systemName: "ellipsis")
                .font(.system(size: uiScale.iconSize(9), weight: .bold))
                .foregroundStyle(palette.tertiaryTextColor)
                .frame(width: uiScale.chromeSize(22), height: uiScale.chromeSize(22))
                .background(Circle().fill(palette.borderColorValue.opacity(0.14)))
            Text(AppStrings.VibeLanes.moreSteps(remainingSteps))
                .font(.system(size: uiScale.textSize(9), weight: .semibold))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var categorySummary: some View {
        if !categories.isEmpty {
            HStack(spacing: uiScale.spacing(10)) {
                ForEach(Array(categories.prefix(2))) { category in
                    VibeCategoryLabel(category: category)
                }
                if categories.count > 2 {
                    Text("+\(categories.count - 2)")
                        .font(.system(size: uiScale.textSize(9), weight: .semibold))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: uiScale.spacing(8)) {
            Label(
                AppStrings.VibeLanes.stepCount(lane.checkpoints.count),
                systemImage: "square.stack.3d.up"
            )
            .font(.system(size: uiScale.textSize(10), weight: .medium))
            .foregroundStyle(palette.secondaryTextColor)
            Spacer()
            if lane.isRunnable, let onStart {
                Button(action: onStart) {
                    Label(AppStrings.VibeLanes.startTask, systemImage: "play.fill")
                        .font(.system(size: uiScale.textSize(10), weight: .semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(AppStrings.VibeLanes.startTask)
                .accessibilityIdentifier("vibeLanes.catalog.start")
            }
            Image(systemName: "arrow.right")
                .font(.system(size: uiScale.iconSize(10), weight: .bold))
                .foregroundStyle(palette.warningColor)
        }
        .padding(.top, uiScale.spacing(9))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.borderColorValue.opacity(0.36))
                .frame(height: uiScale.chromeSize(1))
        }
    }
}
