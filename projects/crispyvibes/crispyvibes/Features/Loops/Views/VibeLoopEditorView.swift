import AppKit
import SwiftUI

@MainActor
struct VibeLoopEditorView: View {
    @Environment(\.appThemePalette) var palette
    @Environment(\.crispyvibesUIScale) var uiScale
    @ObservedObject var manager: VibeLoopManager
    let definition: VibeLoopDefinition?
    let projectOptions: [VibeLoopProjectOption]
    let onSave: (UUID) -> Void
    let onCancel: () -> Void
    let onOpenLane: (UUID?) -> Void
    let onOpenVibes: () -> Void

    @State var name: String
    @State var projectPath: String
    @State var taskInstruction: String
    @State var laneSnapshot: VibeLaneDefinition?
    @State var selectedLaneID: UUID?
    @State var scheduleKind: VibeLoopScheduleKind
    @State var intervalValue: Int
    @State var intervalUnit: VibeLoopIntervalUnit
    @State var intervalAnchor: Date
    @State var scheduleTime: Date
    @State var weekdays: Set<Int>
    @State var timeZoneID: String
    @State var missedRunPolicy: VibeLoopMissedRunPolicy
    @State var isEnabled: Bool
    @State var errorMessage: String?
    @State var pendingFullTrustSave: VibeLoopDefinition?
    @State private var showsAdvanced = false

    init(
        manager: VibeLoopManager,
        definition: VibeLoopDefinition?,
        projectOptions: [VibeLoopProjectOption],
        onSave: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void,
        onOpenLane: @escaping (UUID?) -> Void,
        onOpenVibes: @escaping () -> Void
    ) {
        self.manager = manager
        self.definition = definition
        self.projectOptions = projectOptions
        self.onSave = onSave
        self.onCancel = onCancel
        self.onOpenLane = onOpenLane
        self.onOpenVibes = onOpenVibes

        let initialLane = definition?.laneSnapshot
            ?? manager.laneManager.lanes.first(where: \.isRunnable)
        let schedule = definition?.schedule ?? .daily(
            hour: 9,
            minute: 0,
            timeZoneID: TimeZone.current.identifier
        )
        let decoded = VibeLoopEditorScheduleState.decode(schedule)
        _name = State(initialValue: definition?.name ?? "")
        _projectPath = State(initialValue: definition?.projectPath ?? projectOptions.first?.path ?? "")
        _taskInstruction = State(initialValue: definition?.taskInstruction ?? "")
        _laneSnapshot = State(initialValue: initialLane)
        _selectedLaneID = State(initialValue: initialLane?.id)
        _scheduleKind = State(initialValue: decoded.kind)
        _intervalValue = State(initialValue: decoded.intervalValue)
        _intervalUnit = State(initialValue: decoded.intervalUnit)
        _intervalAnchor = State(initialValue: decoded.anchor)
        _scheduleTime = State(initialValue: decoded.time)
        _weekdays = State(initialValue: decoded.weekdays)
        _timeZoneID = State(initialValue: decoded.timeZoneID)
        _missedRunPolicy = State(initialValue: definition?.missedRunPolicy ?? .runLatestOnce)
        _isEnabled = State(initialValue: definition?.isEnabled ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: uiScale.spacing(28)) {
                            basicsSection
                            sectionDivider
                            laneSection
                        }
                        .frame(minWidth: 470, maxWidth: 610, alignment: .topLeading)

                        Divider()
                            .padding(.horizontal, uiScale.spacing(32))

                        VStack(alignment: .leading, spacing: uiScale.spacing(28)) {
                            scheduleSection
                            sectionDivider
                            advancedSection
                        }
                        .frame(minWidth: 350, maxWidth: 420, alignment: .topLeading)
                    }
                    .frame(maxWidth: 1_100, alignment: .top)

                    VStack(alignment: .leading, spacing: uiScale.spacing(26)) {
                        basicsSection
                        sectionDivider
                        laneSection
                        sectionDivider
                        scheduleSection
                        sectionDivider
                        advancedSection
                    }
                    .frame(maxWidth: 720, alignment: .topLeading)
                }
                .padding(.horizontal, uiScale.spacing(32))
                .padding(.vertical, uiScale.spacing(28))
                .frame(maxWidth: .infinity, alignment: .top)
            }
            footer
        }
        .background(palette.canvasBackgroundColor)
        .onChange(of: selectedLaneID) { _, id in
            guard let id, let lane = manager.laneManager.lane(withID: id) else { return }
            laneSnapshot = lane
        }
        .alert(AppStrings.Loops.fullTrustTitle, isPresented: Binding(
            get: { pendingFullTrustSave != nil },
            set: { if !$0 { pendingFullTrustSave = nil } }
        )) {
            Button(AppStrings.Loops.cancel, role: .cancel) { pendingFullTrustSave = nil }
            Button(AppStrings.Loops.confirmEnable) {
                if let pendingFullTrustSave { commit(pendingFullTrustSave) }
            }
        } message: {
            Text(AppStrings.Loops.fullTrustMessage)
        }
    }

    private var basicsSection: some View {
        editorSection(AppStrings.Loops.details, icon: "slider.horizontal.3") {
            field(AppStrings.Loops.name) {
                TextField(AppStrings.Loops.namePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("loops.editor.name")
            }
            field(AppStrings.Loops.project) {
                HStack(spacing: 8) {
                    TextField(AppStrings.Loops.chooseProject, text: $projectPath)
                        .textFieldStyle(.roundedBorder)
                    if !projectOptions.isEmpty {
                        Menu {
                            ForEach(projectOptions) { project in
                                Button(project.name) { projectPath = project.path }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .menuStyle(.borderlessButton)
                        .help(AppStrings.Loops.knownProjects)
                    }
                    Button(action: chooseProject) {
                        Image(systemName: "folder")
                    }
                    .help(AppStrings.Loops.chooseProject)
                }
            }
            field(AppStrings.Loops.taskInstruction, alignment: .top) {
                ZStack(alignment: .topLeading) {
                    if taskInstruction.isEmpty {
                        Text(AppStrings.Loops.taskPlaceholder)
                            .font(.system(size: uiScale.textSize(13)))
                            .foregroundStyle(palette.tertiaryTextColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $taskInstruction)
                        .font(.system(size: uiScale.textSize(13)))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                }
                .frame(minHeight: uiScale.chromeSize(108))
                .background(palette.canvasSecondaryBackgroundColor, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColorValue.opacity(0.7), lineWidth: 1)
                }
                    .accessibilityIdentifier("loops.editor.instruction")
            }
        }
    }

    private var scheduleSection: some View {
        editorSection(AppStrings.Loops.schedule, icon: "calendar.badge.clock") {
            Picker(AppStrings.Loops.schedule, selection: $scheduleKind) {
                ForEach(VibeLoopScheduleKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch scheduleKind {
            case .interval:
                HStack {
                    Text(AppStrings.Loops.every)
                    TextField("", value: $intervalValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: uiScale.chromeSize(72))
                    Stepper("", value: $intervalValue, in: intervalUnit.minimum...999)
                        .labelsHidden()
                    Picker("", selection: $intervalUnit) {
                        ForEach(VibeLoopIntervalUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .frame(width: uiScale.chromeSize(130))
                    Spacer()
                }
                .onChange(of: intervalUnit) { _, unit in
                    intervalValue = max(intervalValue, unit.minimum)
                }
            case .daily:
                timePicker
            case .weekly:
                VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                    weekdayPicker
                    timePicker
                }
            }

            Label(builtSchedule().summary, systemImage: "clock")
                .font(.system(size: uiScale.textSize(11), weight: .medium))
                .foregroundStyle(Color.accentColor)
                .lineLimit(2)
                .padding(uiScale.spacing(9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var timePicker: some View {
        field(AppStrings.Loops.at) {
            DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: uiScale.spacing(12)) {
            ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                let weekday = index + 1
                Toggle(symbol, isOn: Binding(
                    get: { weekdays.contains(weekday) },
                    set: { selected in
                        if selected { weekdays.insert(weekday) } else { weekdays.remove(weekday) }
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
                if scheduleKind != .interval {
                    field(AppStrings.Loops.timeZone) {
                        Picker("", selection: $timeZoneID) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                                Text(identifier).tag(identifier)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                field(AppStrings.Loops.missedRuns) {
                    Picker("", selection: $missedRunPolicy) {
                        Text(AppStrings.Loops.runLatestOnce).tag(VibeLoopMissedRunPolicy.runLatestOnce)
                        Text(AppStrings.Loops.skipMissed).tag(VibeLoopMissedRunPolicy.skip)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, uiScale.spacing(12))
        } label: {
            HStack(spacing: uiScale.spacing(9)) {
                VibeLaneIconBadge(systemImage: "slider.horizontal.3", side: 28, iconSize: 12)
                Text(AppStrings.Loops.advanced)
                    .font(.system(size: uiScale.textSize(14), weight: .semibold))
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button(AppStrings.Loops.cancel, action: onCancel)
            Button(AppStrings.Loops.savePaused) {
                save(enabled: false)
            }
            .disabled(!hasRequiredFields)
            Button(AppStrings.Loops.reviewAndEnable) {
                save(enabled: true)
            }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("loops.editor.save")
                .disabled(!hasRequiredFields)
        }
        .padding(.horizontal, uiScale.spacing(20))
        .padding(.vertical, uiScale.spacing(12))
        .background(palette.canvasBackgroundColor)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.borderColorValue.opacity(0.5))
                .frame(height: uiScale.chromeSize(1))
        }
    }

    func editorSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
            HStack(spacing: uiScale.spacing(9)) {
                VibeLaneIconBadge(systemImage: icon, side: 28, iconSize: 12)
                Text(title)
                    .font(.system(size: uiScale.textSize(14), weight: .semibold))
            }
            content()
        }
    }

    private var sectionDivider: some View {
        Divider().opacity(0.7)
    }

    func field<Content: View>(
        _ label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: uiScale.spacing(14)) {
            Text(label)
                .font(.system(size: uiScale.textSize(12), weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)
                .frame(width: uiScale.chromeSize(120), alignment: .leading)
            content()
        }
    }

    private var hasRequiredFields: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !taskInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              laneSnapshot?.isRunnable == true else {
            return false
        }
        if scheduleKind == .weekly, weekdays.isEmpty {
            return false
        }
        if scheduleKind == .interval,
           intervalValue * intervalUnit.rawValue < VibeLoopScheduleCalculator.minimumIntervalSeconds {
            return false
        }
        return true
    }
}
