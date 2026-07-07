import SwiftUI

@MainActor
struct VibeLaneContractEditor: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    @Binding var checkpoint: VibeLaneCheckpoint

    init(checkpoint: Binding<VibeLaneCheckpoint>) {
        _checkpoint = checkpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
            Text(AppStrings.VibeLanes.editorContract)
                .font(.system(size: uiScale.textSize(12), weight: .semibold))
                .foregroundStyle(palette.secondaryTextColor)

            requirementsSection
            outputsSection
        }
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            HStack {
                Text(AppStrings.VibeLanes.requiresInputs)
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                Spacer()
                Button { addRequirement() } label: {
                    Label(AppStrings.VibeLanes.addInput, systemImage: "plus")
                }
                .controlSize(.small)
            }

            if checkpoint.inputRequirements.isEmpty {
                Text(AppStrings.VibeLanes.noRequiredInputs)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.tertiaryTextColor)
            } else {
                VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                    ForEach(Array(checkpoint.inputRequirements.indices), id: \.self) { index in
                        requirementRow(index)
                    }
                }
            }
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            HStack {
                Text(AppStrings.VibeLanes.producedOutputs)
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                Spacer()
                Button { addOutput() } label: {
                    Label(AppStrings.VibeLanes.addOutput, systemImage: "plus")
                }
                .controlSize(.small)
            }

            if checkpoint.outputDeclarations.isEmpty {
                Text(AppStrings.VibeLanes.noProducedOutputs)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.tertiaryTextColor)
            } else {
                VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                    ForEach(Array(checkpoint.outputDeclarations.indices), id: \.self) { index in
                        outputRow(index)
                    }
                }
            }
        }
    }

    private func requirementRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: uiScale.spacing(8)) {
                    requirementKeyField(index)
                    Toggle(AppStrings.VibeLanes.askUser, isOn: requirementAskUserBinding(index))
                        .toggleStyle(.checkbox)
                    Spacer()
                    removeRequirementButton(index)
                }
                VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                    HStack {
                        requirementKeyField(index)
                        Spacer()
                        removeRequirementButton(index)
                    }
                    Toggle(AppStrings.VibeLanes.askUser, isOn: requirementAskUserBinding(index))
                        .toggleStyle(.checkbox)
                }
            }
            if checkpoint.inputRequirements[index].askUser {
                TextField(AppStrings.VibeLanes.inputPromptPlaceholder, text: requirementPromptBinding(index), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }
        }
        .padding(uiScale.spacing(10))
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.canvasSecondaryBackgroundColor.opacity(0.65)))
    }

    private func outputRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            HStack(alignment: .top, spacing: uiScale.spacing(8)) {
                TextField(AppStrings.VibeLanes.outputKeyPlaceholder, text: outputKeyBinding(index))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                removeOutputButton(index)
            }
            TextField(AppStrings.VibeLanes.outputDetailPlaceholder, text: outputDetailBinding(index), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
        .padding(uiScale.spacing(10))
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.canvasSecondaryBackgroundColor.opacity(0.65)))
    }

    private func requirementKeyField(_ index: Int) -> some View {
        TextField(AppStrings.VibeLanes.inputKeyPlaceholder, text: requirementKeyBinding(index))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
    }

    private func removeRequirementButton(_ index: Int) -> some View {
        Button(role: .destructive) { removeRequirement(at: index) } label: {
            Image(systemName: "xmark")
                .frame(width: uiScale.chromeSize(24), height: uiScale.chromeSize(22))
        }
        .buttonStyle(.plain)
        .help(AppStrings.VibeLanes.deleteTask)
        .accessibilityLabel(AppStrings.VibeLanes.deleteTask)
    }

    private func removeOutputButton(_ index: Int) -> some View {
        Button(role: .destructive) { removeOutput(at: index) } label: {
            Image(systemName: "xmark")
                .frame(width: uiScale.chromeSize(24), height: uiScale.chromeSize(22))
        }
        .buttonStyle(.plain)
        .help(AppStrings.VibeLanes.deleteTask)
        .accessibilityLabel(AppStrings.VibeLanes.deleteTask)
    }

    private func requirementKeyBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { checkpoint.inputRequirements[index].key },
            set: { value in
                updateRequirement(at: index) { requirement in
                    requirement.key = VibeLaneTaskManager.normalizedKey(value)
                }
            }
        )
    }

    private func requirementAskUserBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { checkpoint.inputRequirements[index].askUser },
            set: { value in updateRequirement(at: index) { $0.askUser = value } }
        )
    }

    private func requirementPromptBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { checkpoint.inputRequirements[index].prompt ?? "" },
            set: { value in
                updateRequirement(at: index) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.prompt = trimmed.isEmpty ? nil : value
                }
            }
        )
    }

    private func outputKeyBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { checkpoint.outputDeclarations[index].key },
            set: { value in
                updateOutput(at: index) { output in
                    output.key = VibeLaneTaskManager.normalizedKey(value)
                }
            }
        )
    }

    private func outputDetailBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { checkpoint.outputDeclarations[index].detail ?? "" },
            set: { value in
                updateOutput(at: index) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.detail = trimmed.isEmpty ? nil : value
                }
            }
        )
    }

    private func addRequirement() {
        var requirements = checkpoint.inputRequirements
        requirements.append(VibeLaneInputRequirement(key: nextKey(prefix: "input", existing: requirements.map(\.key))))
        checkpoint.requires = requirements
    }

    private func removeRequirement(at index: Int) {
        var requirements = checkpoint.inputRequirements
        guard requirements.indices.contains(index) else { return }
        requirements.remove(at: index)
        checkpoint.requires = requirements.isEmpty ? nil : requirements
    }

    private func updateRequirement(at index: Int, mutate: (inout VibeLaneInputRequirement) -> Void) {
        var requirements = checkpoint.inputRequirements
        guard requirements.indices.contains(index) else { return }
        mutate(&requirements[index])
        checkpoint.requires = requirements.filter { !$0.key.isEmpty }.isEmpty ? nil : requirements
    }

    private func addOutput() {
        var outputs = checkpoint.outputDeclarations
        outputs.append(VibeLaneOutputDeclaration(key: nextKey(prefix: "output", existing: outputs.map(\.key))))
        checkpoint.produces = outputs
    }

    private func removeOutput(at index: Int) {
        var outputs = checkpoint.outputDeclarations
        guard outputs.indices.contains(index) else { return }
        outputs.remove(at: index)
        checkpoint.produces = outputs.isEmpty ? nil : outputs
    }

    private func updateOutput(at index: Int, mutate: (inout VibeLaneOutputDeclaration) -> Void) {
        var outputs = checkpoint.outputDeclarations
        guard outputs.indices.contains(index) else { return }
        mutate(&outputs[index])
        checkpoint.produces = outputs.filter { !$0.key.isEmpty }.isEmpty ? nil : outputs
    }

    private func nextKey(prefix: String, existing: [String]) -> String {
        var index = existing.count + 1
        var key = "\(prefix)-\(index)"
        while existing.contains(key) {
            index += 1
            key = "\(prefix)-\(index)"
        }
        return key
    }
}
