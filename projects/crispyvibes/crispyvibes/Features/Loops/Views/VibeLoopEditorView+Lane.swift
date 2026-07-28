import SwiftUI

extension VibeLoopEditorView {
    var laneSection: some View {
        editorSection(AppStrings.Loops.lane, icon: "point.3.connected.trianglepath.dotted") {
            if let laneSnapshot {
                selectedLaneCard(laneSnapshot)
            } else {
                emptyLaneCard
            }
        }
    }

    private func selectedLaneCard(_ lane: VibeLaneDefinition) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            laneHeader(lane)

            if let latest = latestLane(for: lane), latest.version != lane.version {
                laneUpdateBanner(latest)
            }

            Divider()
                .overlay(palette.borderColorValue.opacity(0.42))

            laneRecipe(lane)

            Divider()
                .overlay(palette.borderColorValue.opacity(0.42))

            laneActions
        }
        .background(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                .fill(palette.canvasSecondaryBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                .strokeBorder(palette.borderColorValue.opacity(0.58), lineWidth: uiScale.chromeSize(1))
        )
        .accessibilityIdentifier("loops.editor.selectedLane")
    }

    private func laneHeader(_ lane: VibeLaneDefinition) -> some View {
        HStack(alignment: .top, spacing: uiScale.spacing(11)) {
            VibeLaneIconBadge(
                systemImage: "point.3.connected.trianglepath.dotted",
                color: palette.warningColor,
                side: 36,
                iconSize: 14
            )

            VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
                Text(lane.name)
                    .font(.system(size: uiScale.textSize(15), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)

                if let detail = lane.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: uiScale.spacing(9)) {
                    Text(AppStrings.VibeLanes.vibeVersion(lane.version))
                        .font(.system(size: uiScale.textSize(10), weight: .semibold, design: .monospaced))
                    Label(
                        AppStrings.VibeLanes.stepCount(lane.checkpoints.count),
                        systemImage: "square.stack.3d.up"
                    )
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    VibeLaneStatusChip(
                        text: lane.isRunnable
                            ? AppStrings.VibeLanes.ready
                            : AppStrings.VibeLanes.laneNeedsSetup,
                        color: lane.isRunnable ? palette.successColor : palette.warningColor,
                        icon: lane.isRunnable ? "checkmark" : "exclamationmark",
                        size: 9
                    )
                }
                .foregroundStyle(palette.tertiaryTextColor)
            }
            .layoutPriority(1)

            Spacer(minLength: uiScale.spacing(4))
            laneSelectionMenu(title: AppStrings.Loops.changeLane)
        }
        .padding(uiScale.spacing(14))
    }

    private func laneUpdateBanner(_ latest: VibeLaneDefinition) -> some View {
        HStack(spacing: uiScale.spacing(8)) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: uiScale.iconSize(11), weight: .semibold))
            Text(AppStrings.Loops.laneUpdateAvailable)
                .font(.system(size: uiScale.textSize(11), weight: .medium))
                .lineLimit(2)
            Spacer(minLength: uiScale.spacing(8))
            Button(AppStrings.Loops.updateLane) {
                laneSnapshot = latest
                selectedLaneID = latest.id
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .foregroundStyle(palette.warningColor)
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(9))
        .background(palette.warningColor.opacity(0.08))
    }

    private func laneRecipe(_ lane: VibeLaneDefinition) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            HStack {
                Text(AppStrings.VibeLanes.laneRecipePreview.uppercased())
                    .font(.system(size: uiScale.textSize(9), weight: .bold))
                    .foregroundStyle(palette.tertiaryTextColor)
                Spacer()
                Text(AppStrings.VibeLanes.stepCount(lane.checkpoints.count))
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(palette.secondaryTextColor)
            }

            LazyVGrid(columns: recipeColumns, alignment: .leading, spacing: uiScale.spacing(8)) {
                ForEach(Array(lane.orderedCheckpoints.enumerated()), id: \.offset) { index, checkpoint in
                    laneStep(checkpoint, index: index)
                }
            }
        }
        .padding(uiScale.spacing(14))
    }

    private func laneStep(_ checkpoint: VibeLaneCheckpoint, index: Int) -> some View {
        let vibe = checkpoint.vibeID.flatMap { manager.laneManager.vibe(withID: $0) }
        let category = vibe?.category

        return HStack(spacing: uiScale.spacing(8)) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: uiScale.textSize(10), weight: .bold, design: .monospaced))
                .foregroundStyle(palette.warningColor)
                .frame(width: uiScale.chromeSize(24), height: uiScale.chromeSize(24))
                .background(
                    Circle()
                        .fill(palette.warningColor.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .strokeBorder(palette.warningColor.opacity(0.28), lineWidth: uiScale.chromeSize(1))
                )

            VStack(alignment: .leading, spacing: uiScale.spacing(2)) {
                Text(checkpoint.displayTitle)
                    .font(.system(size: uiScale.textSize(11), weight: .semibold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let category {
                    Label(
                        AppStrings.VibeLanes.vibeCategoryName(category),
                        systemImage: category.systemImage
                    )
                    .font(.system(size: uiScale.textSize(9), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, uiScale.spacing(9))
        .padding(.vertical, uiScale.spacing(8))
        .frame(maxWidth: .infinity, minHeight: uiScale.chromeSize(48), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                .fill(palette.canvasBackgroundColor.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                .strokeBorder(palette.borderColorValue.opacity(0.36), lineWidth: uiScale.chromeSize(1))
        )
        .accessibilityLabel("\(index + 1). \(checkpoint.displayTitle)")
    }

    private var laneActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: uiScale.spacing(10)) {
                laneEditButton
                manageVibesButton
            }
            VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                laneEditButton
                manageVibesButton
            }
        }
        .controlSize(.small)
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(10))
    }

    private var laneEditButton: some View {
        Button {
            let editableID = selectedLaneID.flatMap {
                manager.laneManager.lane(withID: $0)?.id
            }
            onOpenLane(editableID)
        } label: {
            Label(AppStrings.VibeLanes.editLane, systemImage: "pencil")
        }
        .buttonStyle(.borderless)
    }

    private var manageVibesButton: some View {
        Button(action: onOpenVibes) {
            Label(AppStrings.VibeLanes.manageVibes, systemImage: "sparkles.rectangle.stack")
        }
        .buttonStyle(.borderless)
    }

    private var emptyLaneCard: some View {
        HStack(alignment: .center, spacing: uiScale.spacing(12)) {
            VibeLaneIconBadge(
                systemImage: "point.3.connected.trianglepath.dotted",
                color: palette.warningColor,
                side: 36,
                iconSize: 14
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(3)) {
                Text(AppStrings.Loops.chooseLane)
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                Text(AppStrings.VibeLanes.laneCatalogSubtitle)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(2)
            }
            Spacer(minLength: uiScale.spacing(8))
            laneSelectionMenu(title: AppStrings.Loops.choose)
        }
        .padding(uiScale.spacing(14))
        .background(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                .fill(palette.canvasSecondaryBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                .strokeBorder(palette.warningColor.opacity(0.30), lineWidth: uiScale.chromeSize(1))
        )
    }

    private func laneSelectionMenu(title: String) -> some View {
        Menu {
            if let laneSnapshot,
               manager.laneManager.lane(withID: laneSnapshot.id) == nil {
                Button {} label: {
                    Label(
                        "\(laneSnapshot.name) · \(AppStrings.VibeLanes.vibeVersion(laneSnapshot.version))",
                        systemImage: "checkmark"
                    )
                }
                .disabled(true)
                Divider()
            }

            ForEach(manager.laneManager.lanes) { lane in
                Button {
                    selectedLaneID = lane.id
                    laneSnapshot = lane
                } label: {
                    Label(
                        laneMenuTitle(lane),
                        systemImage: laneSnapshot?.id == lane.id
                            ? "checkmark"
                            : "point.3.connected.trianglepath.dotted"
                    )
                }
                .disabled(!lane.isRunnable)
            }
        } label: {
            Label(title, systemImage: "arrow.up.arrow.down")
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(AppStrings.Loops.chooseLane)
    }

    private func laneMenuTitle(_ lane: VibeLaneDefinition) -> String {
        let version = AppStrings.VibeLanes.vibeVersion(lane.version)
        guard !lane.isRunnable else { return "\(lane.name) · \(version)" }
        return "\(lane.name) · \(AppStrings.VibeLanes.laneNeedsSetup)"
    }

    private func latestLane(for lane: VibeLaneDefinition) -> VibeLaneDefinition? {
        manager.laneManager.lane(withID: lane.id)
    }

    private var recipeColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: uiScale.chromeSize(150),
                    maximum: uiScale.chromeSize(240)
                ),
                spacing: uiScale.spacing(8),
                alignment: .top
            )
        ]
    }
}
