import SwiftUI

/// Title-bar toolbar button that opens a popover for creating a new terminal.
/// The popover lists open projects (creates a persistent tile/pane), accepts
/// a custom path, and exposes a "Temporary Terminal" shortcut targeting the
/// currently focused project. Each row posts `.createTerminalRequested` with
/// the chosen directory URL, optional owning project path, and a
/// `preferTemporary` flag; `ContentView` listens and dispatches based on
/// the current canvas mode (or unconditionally to a spotlight terminal when
/// `preferTemporary` is set).
struct NewTerminalToolbarButton: View {
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let projects: [AnyProjectSession]
    let focusedProject: AnyProjectSession?
    /// Returns the project's assigned color tag. Used to color the project
    /// rows. The closure path bypasses the path-keyed `projectColorTagsByPath`
    /// dict, which keys things by `rootURL.standardizedFileURL.path` — for
    /// remote (SSH) projects that key is wrong because their canonical color
    /// storage uses `projectIdentifier` (the SSH URI). Calling `colorTag(for:)`
    /// directly resolves correctly for both local and remote projects.
    let colorForProject: (AnyProjectSession) -> Color?
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            HomeToolbarIconLabel(systemName: "terminal")
        }
        .help(AppStrings.Terminal.newTerminal)
        .accessibilityIdentifier("toolbar.new-terminal")
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            // SwiftUI `.popover()` content runs in a fresh hosting view
            // whose environment is detached from the presenting view's
            // chain — custom env values fall back to their hard-coded
            // defaults. Re-inject the values we read at this level so the
            // popover renders against the same theme/scale as the rest of
            // the app. Accent tint is also re-applied here so buttons
            // inside the popover use the proper accent color (the toolbar
            // itself intentionally does not inherit accent tint to avoid
            // tinting Menu label icons).
            NewTerminalPopover(
                projects: projects,
                focusedProject: focusedProject,
                colorForProject: colorForProject,
                onSubmit: {
                    isShowingPopover = false
                }
            )
            .environment(\.crispyvibesTheme, theme)
            .environment(\.appThemePalette, palette)
            .environment(\.crispyvibesUIScale, uiScale)
            .applyingAppAccentTheme(palette.accentColor)
        }
    }
}

/// Popover content for `NewTerminalToolbarButton`. Renders, top to bottom:
///
/// 1. A "Temporary Terminal" shortcut targeting the currently focused
///    project (visible only when one exists).
/// 2. The project picker — clicking a project opens a board tile in
///    terminal-board mode or a spotlight terminal in detailed mode.
/// 3. A custom path text field for one-off directories.
struct NewTerminalPopover: View {
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let projects: [AnyProjectSession]
    let focusedProject: AnyProjectSession?
    let colorForProject: (AnyProjectSession) -> Color?
    /// Called after a notification has been posted. The host typically uses
    /// this to dismiss the popover.
    let onSubmit: () -> Void

    @State private var customPath: String = ""
    @FocusState private var isCustomPathFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let focusedProject {
                temporaryTerminalRow(for: focusedProject)
                Divider()
            }
            projectList
            Divider()
            customPathField
        }
        .frame(width: 340)
        .frame(minHeight: 180)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(AppTypographyTokens.scaledIcon(13, weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)
            Text(AppStrings.Terminal.newTerminal)
                .font(AppTypographyTokens.subheadlineSemibold)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Temporary terminal row

    private func temporaryTerminalRow(for project: AnyProjectSession) -> some View {
        let url = project.rootURL.standardizedFileURL
        let projectColor = colorForProject(project) ?? palette.accentColor
        return Button {
            submit(directoryURL: url, projectPath: url.path, preferTemporary: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(AppTypographyTokens.scaledIcon(13))
                    .foregroundStyle(projectColor)
                    .frame(width: uiScale.iconSize(14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Temporary Terminal")
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                    Text("In \(url.lastPathComponent) — closes when dismissed")
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Project list

    @ViewBuilder
    private var projectList: some View {
        if projects.isEmpty {
            HStack {
                Spacer()
                Text("No projects in this vibespace")
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                Spacer()
            }
            .padding(.vertical, 14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(projects, id: \.id) { project in
                        projectRow(project)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 200)
        }
    }

    private func projectRow(_ project: AnyProjectSession) -> some View {
        let url = project.rootURL.standardizedFileURL
        let displayPath = VibeSpaceDirectoryCandidate.formatDisplayPath(for: url.path)
        let projectColor = colorForProject(project) ?? palette.accentColor
        return Button {
            submit(directoryURL: url, projectPath: url.path, preferTemporary: false)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(AppTypographyTokens.scaledIcon(11))
                    .foregroundStyle(projectColor)
                    .frame(width: uiScale.iconSize(14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                    Text(displayPath)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom path

    private var customPathField: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.plus")
                .font(AppTypographyTokens.scaledIcon(11))
                .foregroundStyle(palette.tertiaryTextColor)
            TextField("Custom path… (e.g. ~/code/scratch)", text: $customPath)
                .textFieldStyle(.plain)
                .font(AppTypographyTokens.caption)
                .focused($isCustomPathFocused)
                .onSubmit { submitCustomPath() }
            Button {
                submitCustomPath()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(AppTypographyTokens.scaledIcon(13))
                    .foregroundStyle(resolvedCustomURL == nil ? palette.tertiaryTextColor : palette.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(resolvedCustomURL == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Submission

    private var resolvedCustomURL: URL? {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = trimmed.hasPrefix("~/")
            ? NSHomeDirectory() + trimmed.dropFirst(1)
            : trimmed
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private func submitCustomPath() {
        guard let url = resolvedCustomURL else { return }
        submit(
            directoryURL: url,
            projectPath: inferredProjectPath(for: url),
            preferTemporary: false
        )
    }

    private func submit(directoryURL: URL, projectPath: String?, preferTemporary: Bool) {
        var userInfo: [String: Any] = [
            AppCommandUserInfoKey.currentDirectoryURL: directoryURL
        ]
        if let projectPath {
            userInfo[AppCommandUserInfoKey.projectPath] = projectPath
        }
        if preferTemporary {
            userInfo[AppCommandUserInfoKey.preferTemporary] = true
        }
        NotificationCenter.default.post(
            name: .createTerminalRequested,
            object: nil,
            userInfo: userInfo
        )
        onSubmit()
    }

    private func inferredProjectPath(for directoryURL: URL) -> String? {
        let dirPath = directoryURL.standardizedFileURL.path
        return projects
            .map { $0.rootURL.standardizedFileURL.path }
            .filter { dirPath == $0 || dirPath.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }
}
