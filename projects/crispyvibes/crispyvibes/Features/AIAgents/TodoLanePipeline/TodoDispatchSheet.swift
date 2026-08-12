import SwiftUI

/// F060 — the "Send to Lane…" sheet on a todo: pick a lane, review the
/// pre-filled first-checkpoint inputs, fill or knowingly skip unresolved ones,
/// dispatch. Calls the same bridge method as `crispy todo dispatch` (one code
/// path, two callers — F060-R03/R09).
struct TodoDispatchSheet: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var bridge: TodoLanePipelineBridge
    let todo: Todo
    /// Project used when the todo is vibespace-level (nil projectPath).
    let fallbackProjectPath: String?

    @State private var selectedLaneID: UUID?
    @State private var inputDrafts: [String: String] = [:]
    @State private var isDispatching = false
    @State private var errorText: String?

    private var catalog: [VibeLaneCatalogEntry] { bridge.laneCatalog() }
    private var selectedEntry: VibeLaneCatalogEntry? {
        catalog.first { $0.laneID == selectedLaneID }
    }

    /// Keys the selected lane requires, with their current draft/seed value.
    private var requiredKeys: [(key: String, seeded: String?)] {
        guard let entry = selectedEntry else { return [] }
        let seed = bridge.seededInputs(for: todo)
        return entry.firstCheckpointRequires.keys.sorted().map { key in
            (key, inputDrafts[key]?.isEmpty == false ? inputDrafts[key] : seed[key])
        }
    }

    private var unresolvedKeys: [String] {
        requiredKeys.filter { $0.seeded == nil }.map(\.key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
            Text(AppStrings.TodoPipeline.chooseLane)
                .font(.system(size: uiScale.textSize(15), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)

            lanePicker

            if selectedEntry != nil {
                inputsSection
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.errorColor)
            }

            HStack {
                Button(AppStrings.VibeLanes.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(dispatchButtonTitle) {
                    Task { await performDispatch() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedLaneID == nil || isDispatching)
            }
        }
        .padding(uiScale.spacing(18))
        .frame(width: 440)
        .background(palette.canvasBackgroundColor)
        .onAppear {
            // Preselect the triage suggestion when it points at a real lane.
            if let suggested = todo.triage?.suggestedLane?.laneID,
               catalog.contains(where: { $0.laneID == suggested }) {
                selectedLaneID = suggested
            }
        }
    }

    private var dispatchButtonTitle: String {
        unresolvedKeys.isEmpty
            ? AppStrings.TodoPipeline.dispatch
            : AppStrings.TodoPipeline.dispatchAnyway
    }

    private var lanePicker: some View {
        Picker(AppStrings.VibeLanes.route, selection: $selectedLaneID) {
            Text("—").tag(UUID?.none)
            ForEach(catalog, id: \.laneID) { entry in
                Text(entry.name).tag(UUID?.some(entry.laneID))
            }
        }
        .pickerStyle(.menu)
    }

    private var inputsSection: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            if !requiredKeys.isEmpty {
                if !unresolvedKeys.isEmpty {
                    Text(AppStrings.TodoPipeline.unresolvedInputs)
                        .font(.system(size: uiScale.textSize(11), weight: .medium))
                        .foregroundStyle(palette.secondaryTextColor)
                }
                ForEach(requiredKeys, id: \.key) { item in
                    HStack(spacing: uiScale.spacing(8)) {
                        Text(item.key)
                            .font(.system(size: uiScale.textSize(11), weight: .medium))
                            .foregroundStyle(item.seeded == nil ? palette.errorColor : palette.secondaryTextColor)
                            .frame(width: 110, alignment: .trailing)
                        TextField(
                            "",
                            text: Binding(
                                get: { inputDrafts[item.key] ?? item.seeded ?? "" },
                                set: { inputDrafts[item.key] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: uiScale.textSize(11)))
                    }
                }
            }
        }
    }

    private func performDispatch() async {
        guard let selectedLaneID else { return }
        isDispatching = true
        defer { isDispatching = false }
        let overrides = inputDrafts.filter { !$0.value.isEmpty }
        let outcome = await bridge.dispatch(
            todoID: todo.id,
            laneReference: selectedLaneID.uuidString,
            overrides: overrides,
            allowUnresolved: true,   // the sheet has already surfaced the gaps
            projectPathFallback: fallbackProjectPath
        )
        switch outcome {
        case .dispatched:
            dismiss()
        case .activeTaskExists:
            errorText = AppStrings.TodoPipeline.taskRunning
        case .unresolvedInputs(let keys):
            errorText = "\(AppStrings.TodoPipeline.unresolvedInputs) \(keys.joined(separator: ", "))"
        case .laneAmbiguous, .laneNotFound, .todoNotFound, .creationFailed:
            errorText = AppStrings.TodoPipeline.dispatchFailed
        }
    }
}
