import AppKit
import Foundation

extension VibeLoopEditorView {
    func save(enabled: Bool) {
        isEnabled = enabled
        guard let proposed = proposedDefinition() else {
            errorMessage = AppStrings.Loops.validationRequired
            return
        }
        if let failure = manager.validationFailure(for: proposed) {
            errorMessage = failure.detail
            return
        }
        let requiresConfirmation = proposed.isEnabled
            && (definition == nil
                || definition?.isEnabled == false
                || definition?.laneSnapshot != proposed.laneSnapshot)
        if requiresConfirmation {
            pendingFullTrustSave = proposed
        } else {
            commit(proposed)
        }
    }

    func commit(_ proposed: VibeLoopDefinition) {
        Task { await commitPersisted(proposed) }
    }

    private func commitPersisted(_ proposed: VibeLoopDefinition) async {
        guard await manager.save(proposed) else {
            errorMessage = manager.validationFailure(for: proposed)?.detail ?? AppStrings.Loops.saveFailed
            return
        }
        pendingFullTrustSave = nil
        onSave(proposed.id)
    }

    func proposedDefinition() -> VibeLoopDefinition? {
        guard let laneSnapshot else { return nil }
        let now = Date()
        return VibeLoopDefinition(
            id: definition?.id ?? UUID(),
            name: name,
            isEnabled: isEnabled,
            projectPath: projectPath,
            taskInstruction: taskInstruction,
            laneSnapshot: laneSnapshot,
            schedule: builtSchedule(),
            missedRunPolicy: missedRunPolicy,
            createdAt: definition?.createdAt ?? now,
            updatedAt: now
        )
    }

    func builtSchedule() -> VibeLoopSchedule {
        let components = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        switch scheduleKind {
        case .interval:
            return .interval(
                anchor: intervalAnchor,
                seconds: max(1, intervalValue) * intervalUnit.rawValue
            )
        case .daily:
            return .daily(hour: hour, minute: minute, timeZoneID: timeZoneID)
        case .weekly:
            return .weekly(weekdays: weekdays, hour: hour, minute: minute, timeZoneID: timeZoneID)
        }
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppStrings.Loops.chooseProject
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.standardizedFileURL.path
        }
    }
}
