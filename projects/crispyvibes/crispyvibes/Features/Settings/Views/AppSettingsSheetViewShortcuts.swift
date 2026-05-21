import AppKit
import SwiftUI

extension AppSettingsSheetView {
    var shortcutsCategoryContent: some View {
        Group {
            SettingsCard(
                title: "App Shortcuts",
                description: "Customize app-wide navigation, editor, project, and appearance shortcuts. Press Delete while recording to disable a shortcut, or Escape to cancel. Reset always returns a shortcut to the app default. Numbered project focus shortcuts stay fixed and are listed here for reference."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if let message = appShortcutSettingsStore.message, !message.isEmpty {
                        Text(message)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.warningColor)
                    }

                    Text("These are global app shortcuts. VibeSpace command shortcuts live in VibeSpace Settings and only apply to the active VibeSpace.")
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)

                    Button("Reset All App Shortcuts to Defaults") {
                        appShortcutSettingsStore.resetAll()
                    }
                    .buttonStyle(.crispyvibesText)
                    .accessibilityIdentifier("app.settings.shortcuts.reset-all")

                    SettingsFieldRow(
                        title: AppStrings.Settings.Terminal.inlineTriggerTitle,
                        detail: AppStrings.Settings.Terminal.inlineTriggerDetail
                    ) {
                        TextField(
                            AppPreferences.defaultTerminalComposeInlineTrigger,
                            text: Binding(
                                get: { AppPreferences.normalizedTerminalComposeInlineTrigger(terminalComposeInlineTrigger) },
                                set: { terminalComposeInlineTrigger = AppPreferences.normalizedTerminalComposeInlineTrigger($0) }
                            )
                        )
                        .textFieldStyle(SquareBorderTextFieldStyle())
                        .accessibilityIdentifier("app.settings.shortcuts.terminal-inline-trigger")
                    }
                }
            }

            ForEach(AppShortcutSection.allCases) { section in
                let rows = appShortcutSettingsStore.rows.filter { $0.section == section }
                if !rows.isEmpty {
                    SettingsCard(title: section.title, description: nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(rows) { row in
                                AppShortcutSettingsRowView(
                                    row: row,
                                    onUpdate: { appShortcutSettingsStore.setBinding($0, for: row.action) },
                                    onReset: { appShortcutSettingsStore.reset(row.action) }
                                )
                            }
                        }
                    }
                }
            }

        }
        .onAppear {
            appShortcutSettingsStore.reload()
        }
    }
}

private struct AppShortcutSettingsRowView: View {
    @Environment(\.appThemePalette) private var appThemePalette

    let row: AppShortcutSettingsRow
    let onUpdate: (AppShortcutBinding?) -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(AppTypographyTokens.settingsFieldTitle)
                Text(detailText)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
            .frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)

            if row.isEditable {
                AppShortcutRecorderButton(
                    binding: row.currentBinding,
                    onUpdate: onUpdate
                )
                .frame(width: 190, alignment: .leading)
            } else {
                Text(row.currentBinding?.displayString ?? "Not Set")
                    .font(AppTypographyTokens.settingsFieldTitle)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .frame(width: 190, alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 6) {
                Text(statusText)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)

                if row.isEditable {
                    HStack(spacing: 8) {
                        if row.currentBinding != nil {
                            Button("Disable") {
                                onUpdate(nil)
                            }
                            .buttonStyle(.crispyvibesText)
                        }

                        if row.isCustomized {
                            Button("Reset to Default") {
                                onReset()
                            }
                            .buttonStyle(.crispyvibesText)
                        }
                    }
                }
            }
            .frame(width: 190, alignment: .trailing)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var detailText: String {
        if let defaultBinding = row.defaultBinding {
            return "Default: \(defaultBinding.displayString)"
        }
        return "No default shortcut"
    }

    private var statusText: String {
        if !row.isEditable {
            return "Fixed"
        }
        if row.currentBinding == nil {
            return row.isCustomized ? "Disabled override" : "Disabled"
        }
        return row.isCustomized ? "Customized" : "Default"
    }
}

private struct AppShortcutRecorderButton: View {
    @Environment(\.appThemePalette) private var appThemePalette

    let binding: AppShortcutBinding?
    let onUpdate: (AppShortcutBinding?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                    .font(AppTypographyTokens.scaledSystem(12, weight: .medium))

                Text(labelText)
                    .font(AppTypographyTokens.settingsFieldTitle)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isRecording ? appThemePalette.primaryTextColor : appThemePalette.secondaryTextColor)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appThemePalette.canvasBackgroundColor.opacity(isRecording ? 0.85 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isRecording
                            ? appThemePalette.accentColor.opacity(0.75)
                            : appThemePalette.borderColorValue.opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stopRecording)
    }

    private var labelText: String {
        if isRecording {
            return "Type Shortcut…"
        }
        return binding?.displayString ?? "Not Set"
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = AppShortcutBinding.normalizedModifierFlags(event.modifierFlags)
            if event.keyCode == 53, modifiers.isEmpty {
                stopRecording()
                return nil
            }
            if (event.keyCode == 51 || event.keyCode == 117), modifiers.isEmpty {
                onUpdate(nil)
                stopRecording()
                return nil
            }
            guard !modifiers.isEmpty else {
                NSSound.beep()
                return nil
            }
            onUpdate(AppShortcutBinding(keyCode: event.keyCode, modifiers: modifiers))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
