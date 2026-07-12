import SwiftUI

/// A project option for the quick-capture target picker (root path + display name).
struct TodoCaptureProject: Identifiable, Equatable {
    /// Standardized project root path; also the value passed to `store.add(projectPath:)`.
    let id: String
    let name: String
}

/// F053 — instant "capture and forget" HUD. Invoked by a hotkey (⌃⌘T):
/// a centered floating field appears focused; type and press Return to save.
/// A footer shows the target project (defaulting to the currently-focused one,
/// snapshotted on open) and lets the user retarget to another project or the
/// vibespace inbox. Esc or a click outside cancels.
struct TodoQuickCaptureOverlay: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var uiScale
    let store: VibeSpaceTodoStore
    let projects: [TodoCaptureProject]
    /// The focused project's path at the moment the HUD opened (the default target).
    let initialProjectPath: String?
    let onClose: () -> Void

    @State private var text = ""
    @State private var selectedPath: String?
    @State private var phase: Phase = .editing
    @FocusState private var fieldFocused: Bool

    private enum Phase: Equatable {
        case editing
        case saving
        case saved
        case failed(String)
    }

    private var selectedProjectName: String {
        if let selectedPath, let match = projects.first(where: { $0.id == selectedPath }) {
            return match.name
        }
        return AppStrings.Todos.captureNoProject
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                switch phase {
                case .saved:
                    successView
                case .editing, .saving, .failed:
                    captureField
                    if case let .failed(message) = phase {
                        failureBar(message)
                    }
                    Divider().overlay(palette.borderColorValue.opacity(0.3))
                    projectFooter
                }
            }
            .frame(width: uiScale.chromeSize(520))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: phase)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: theme.radius(12)))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(12))
                    .stroke(palette.borderColorValue.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            .padding(.top, uiScale.spacing(140))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onClose)
        .onAppear {
            selectedPath = initialProjectPath
            fieldFocused = true
        }
        .onChange(of: selectedPath) {
            // Picking a project closes the menu and steals focus; restore it so
            // the user can keep typing without clicking back into the field.
            DispatchQueue.main.async { fieldFocused = true }
        }
        .transition(.opacity)
    }

    private var captureField: some View {
        HStack(spacing: uiScale.spacing(12)) {
            Image(systemName: "checklist")
                .font(.system(size: uiScale.iconSize(15)))
                .foregroundStyle(palette.accentColor)
            TextField("", text: $text, prompt: Text(AppStrings.Todos.quickCapturePlaceholder).foregroundStyle(palette.tertiaryTextColor))
                .textFieldStyle(.plain)
                .font(.system(size: uiScale.textSize(16)))
                .foregroundStyle(palette.primaryTextColor)
                .focused($fieldFocused)
                .disabled(phase == .saving)
                .onSubmit(save)
        }
        .padding(.horizontal, uiScale.spacing(16))
        .frame(height: uiScale.chromeSize(52))
    }

    private var projectFooter: some View {
        HStack(spacing: uiScale.spacing(6)) {
            Text(AppStrings.Todos.captureLandsIn)
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.tertiaryTextColor)
            Menu {
                ForEach(projects) { project in
                    Button {
                        selectedPath = project.id
                    } label: {
                        Label(project.name, systemImage: project.id == selectedPath ? "checkmark" : "folder")
                    }
                }
                if !projects.isEmpty { Divider() }
                Button {
                    selectedPath = nil
                } label: {
                    Label(AppStrings.Todos.captureNoProject, systemImage: selectedPath == nil ? "checkmark" : "square.stack.3d.up")
                }
            } label: {
                HStack(spacing: uiScale.spacing(4)) {
                    Image(systemName: "folder").font(.system(size: uiScale.iconSize(11)))
                    Text(selectedProjectName)
                        .font(.system(size: uiScale.textSize(12), weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: uiScale.iconSize(9)))
                }
                .foregroundStyle(palette.secondaryTextColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, uiScale.spacing(16))
        .padding(.vertical, uiScale.spacing(8))
    }

    private func failureBar(_ message: String) -> some View {
        HStack(spacing: uiScale.spacing(6)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: uiScale.iconSize(11)))
                .foregroundStyle(palette.warningColor)
            Text("\(AppStrings.Todos.captureFailed): \(message)")
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, uiScale.spacing(16))
        .padding(.bottom, uiScale.spacing(8))
    }

    private var successView: some View {
        HStack(spacing: uiScale.spacing(10)) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: uiScale.iconSize(18)))
                .foregroundStyle(palette.successColor)
                .symbolEffect(.bounce, value: phase)
            Text(AppStrings.Todos.captureAdded)
                .font(.system(size: uiScale.textSize(15), weight: .medium))
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
        }
        .padding(.horizontal, uiScale.spacing(16))
        .frame(height: uiScale.chromeSize(52))
        .transition(.opacity)
    }

    private func save() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { onClose(); return }
        guard phase != .saving else { return }
        phase = .saving
        let path = selectedPath
        Task {
            // Confirm only after the write actually lands; keep the text on
            // failure so the capture isn't silently lost (spec F053-R03).
            if await store.add(title: title, projectPath: path) != nil {
                phase = .saved
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                onClose()
            } else {
                phase = .failed(store.lastErrorMessage ?? AppStrings.Todos.captureFailed)
                fieldFocused = true
            }
        }
    }
}
