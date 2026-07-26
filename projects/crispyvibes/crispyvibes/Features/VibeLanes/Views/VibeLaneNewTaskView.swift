import AppKit
import SwiftUI

// F059 — the "new task" screen: describe the work, pick a lane, review, and start.
// A task must run inside an explicit project (finding #4), so Start is disabled
// until one is focused. Split out of VibeLaneSurfaceView.swift for file size /
// one-primary-type-per-file (coding-guidelines).

@MainActor
struct VibeLaneNewTaskView: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.appThemePalette) private var palette
    @ObservedObject var manager: VibeLaneTaskManager
    let focusedProjectPath: String?
    let onStarted: (VibeLaneTask) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var selectedLaneID: UUID?
    @State private var laneChosenByUser = false
    @State private var startFailed = false
    /// User override of the focused project (via the directory picker).
    @State private var customProjectPath: String?

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var selectedLane: VibeLaneDefinition? { selectedLaneID.flatMap { manager.lane(withID: $0) } }

    private var suggestedLaneID: UUID? {
        let runnableLanes = manager.lanes.filter(\.isRunnable)
        guard !runnableLanes.isEmpty else { return nil }
        let lowercased = title.lowercased()
        if lowercased.contains("bug") || lowercased.contains("fix") || lowercased.contains("fail") || lowercased.contains("test") {
            return runnableLanes.first { $0.name.localizedCaseInsensitiveContains("bug") }?.id ?? runnableLanes.first?.id
        }
        if lowercased.contains("feature") || lowercased.contains("add") || lowercased.contains("build") {
            return runnableLanes.first { $0.name.localizedCaseInsensitiveContains("feature") }?.id ?? runnableLanes.first?.id
        }
        return runnableLanes.first?.id
    }

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: uiScale.spacing(22)) {
                    VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
                        taskPrompt
                        if resolvedProjectPath == nil {
                            noProjectNotice
                        }
                        if startFailed {
                            failureMessage
                        }
                        actions
                    }
                    .frame(width: uiScale.chromeSize(360), alignment: .topLeading)

                    VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
                        lanePicker
                        if let selectedLane {
                            reviewPanel(selectedLane)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: uiScale.spacing(18)) {
                    taskPrompt
                    lanePicker
                    if let selectedLane {
                        reviewPanel(selectedLane)
                    }
                    if resolvedProjectPath == nil {
                        noProjectNotice
                    }
                    if startFailed {
                        failureMessage
                    }
                    actions
                }
            }
            .padding(uiScale.spacing(24))
            .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(palette.canvasBackgroundColor)
        .onAppear { selectedLaneID = selectedLaneID ?? suggestedLaneID }
        .onChange(of: title) { _, _ in
            if !laneChosenByUser {
                selectedLaneID = suggestedLaneID
            }
        }
    }

    private var taskPrompt: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            sectionHeader(step: 1, title: AppStrings.VibeLanes.describeTask)
            TextField(AppStrings.VibeLanes.taskPlaceholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(5...10)
                .font(.system(size: uiScale.textSize(14)))
                .padding(uiScale.spacing(12))
                .vibeLaneCard(cornerRadius: 10)
        }
    }

    private func sectionHeader(step: Int, title: String) -> some View {
        HStack(spacing: uiScale.spacing(8)) {
            Text("\(step)")
                .font(.system(size: uiScale.textSize(11), weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: uiScale.chromeSize(20), height: uiScale.chromeSize(20))
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
            Text(title)
                .font(.system(size: uiScale.textSize(15), weight: .semibold))
        }
    }

    private var lanePicker: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            sectionHeader(step: 2, title: AppStrings.VibeLanes.chooseRoute)
            VStack(spacing: 0) {
                ForEach(Array(manager.lanes.enumerated()), id: \.element.id) { index, lane in
                    laneRow(lane)
                    if index < manager.lanes.count - 1 {
                        Divider().padding(.leading, uiScale.chromeSize(42))
                    }
                }
            }
            .padding(uiScale.spacing(4))
            .vibeLaneCard()
        }
    }

    private func laneRow(_ lane: VibeLaneDefinition) -> some View {
        let isSelected = selectedLaneID == lane.id
        let isSuggested = suggestedLaneID == lane.id
        return Button {
            laneChosenByUser = true
            selectedLaneID = lane.id
        } label: {
            HStack(alignment: .top, spacing: uiScale.spacing(10)) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: uiScale.iconSize(14)))
                    .foregroundStyle(isSelected ? Color.accentColor : palette.tertiaryTextColor)
                    .frame(width: uiScale.chromeSize(20))

                VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
                    HStack(spacing: uiScale.spacing(8)) {
                        Text(lane.name)
                            .font(.system(size: uiScale.textSize(13), weight: .semibold))
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                        if isSuggested {
                            Text(AppStrings.VibeLanes.suggested)
                                .font(.system(size: uiScale.textSize(10), weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        if !lane.isRunnable {
                            Label(AppStrings.VibeLanes.laneNeedsSetup, systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: uiScale.textSize(10), weight: .semibold))
                                .foregroundStyle(Color.orange)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(lane.detail ?? AppStrings.VibeLanes.noLaneDetail)
                        .font(.system(size: uiScale.textSize(12)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(2)
                    Text(lane.routeSummary)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.tertiaryTextColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, uiScale.spacing(12))
            .padding(.vertical, uiScale.spacing(11))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!lane.isRunnable)
        .vibeLaneHoverable()
    }

    private func reviewPanel(_ lane: VibeLaneDefinition) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
            Text(AppStrings.VibeLanes.reviewRun)
                .font(.system(size: uiScale.textSize(13), weight: .semibold))
                .foregroundStyle(palette.secondaryTextColor)
            projectRow
            labeledValue(AppStrings.VibeLanes.lane, value: lane.name)
            VibeLaneRoutePreview(lane: lane)
        }
        .padding(uiScale.spacing(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .vibeLaneCard()
    }

    /// The project the task will run in, with an explicit picker so the user is
    /// never locked to the focused project.
    private var projectRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppStrings.VibeLanes.project)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            HStack(spacing: uiScale.spacing(8)) {
                Text(resolvedProjectPath ?? AppStrings.VibeLanes.noProjectShort)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(resolvedProjectPath == nil ? palette.tertiaryTextColor : palette.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(AppStrings.VibeLanes.chooseProject, action: pickProjectDirectory)
                    .buttonStyle(.link)
                    .font(.system(size: uiScale.textSize(12)))
                if customProjectPath != nil, focusedProjectPath != nil {
                    Button(AppStrings.VibeLanes.useFocusedProject) { customProjectPath = nil }
                        .buttonStyle(.link)
                        .font(.system(size: uiScale.textSize(12)))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func pickProjectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppStrings.VibeLanes.chooseProject
        if let current = resolvedProjectPath {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            customProjectPath = url.path
        }
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            Text(value)
                .font(.system(size: uiScale.textSize(12)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var actions: some View {
        HStack(spacing: uiScale.spacing(10)) {
            Button(action: start) { Label(AppStrings.VibeLanes.startTask, systemImage: "play.fill") }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                trimmedTitle.isEmpty
                    || selectedLane?.isRunnable != true
                    || resolvedProjectPath == nil
            )

            Button(AppStrings.VibeLanes.cancel, action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryTextColor)
        }
    }

    private var failureMessage: some View {
        Text(AppStrings.VibeLanes.startFailed)
            .font(.system(size: uiScale.textSize(12)))
            .foregroundStyle(.red)
    }

    private var noProjectNotice: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(8)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(AppStrings.VibeLanes.noProjectSelected)
                .font(.system(size: uiScale.textSize(12)))
                .foregroundStyle(palette.secondaryTextColor)
            Button(AppStrings.VibeLanes.chooseProject, action: pickProjectDirectory)
                .buttonStyle(.link)
                .font(.system(size: uiScale.textSize(12), weight: .semibold))
        }
        .padding(uiScale.spacing(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .vibeLaneCard(cornerRadius: 10, tint: .orange)
    }

    /// The project the task will run in: the user's explicit choice, else the
    /// focused project. No home-directory fallback: a Vibe Lane task must run
    /// inside an explicit project (finding #4), so this stays nil until one is
    /// focused or chosen, which disables Start.
    private var resolvedProjectPath: String? {
        if let custom = customProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        let trimmed = focusedProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func start() {
        Task { await startTask() }
    }

    private func startTask() async {
        guard let laneID = selectedLaneID, let projectPath = resolvedProjectPath else { return }
        guard let task = await manager.createTask(
            laneID: laneID,
            title: trimmedTitle,
            projectPath: projectPath
        ) else {
            startFailed = true
            return
        }
        onStarted(task)
    }
}

/// Compact chevron-separated route of a lane's checkpoints. Tightly coupled to
/// the new-task review panel, so it lives alongside it.
@MainActor
private struct VibeLaneRoutePreview: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.appThemePalette) private var palette
    let lane: VibeLaneDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(7)) {
            Text(AppStrings.VibeLanes.route)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                ForEach(Array(lane.orderedCheckpoints.enumerated()), id: \.element.key) { index, checkpoint in
                    HStack(alignment: .top, spacing: uiScale.spacing(8)) {
                        Text("\(index + 1)")
                            .font(.system(size: uiScale.textSize(10), weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.tertiaryTextColor)
                            .frame(width: uiScale.chromeSize(18), alignment: .trailing)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(checkpoint.displayTitle)
                                .font(.system(size: uiScale.textSize(11), weight: .medium))
                                .foregroundStyle(palette.secondaryTextColor)
                            VibeLaneEngineSummaryView(configuration: checkpoint.engine)
                        }
                    }
                }
            }
        }
    }
}
