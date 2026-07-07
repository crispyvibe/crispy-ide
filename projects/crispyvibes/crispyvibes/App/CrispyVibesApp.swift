import AppKit
import SwiftUI

extension Notification.Name {
    static let saveCurrentMarkdown = Notification.Name("saveCurrentMarkdown")
    static let vibespaceFileDidSave = Notification.Name("vibespaceFileDidSave")
    static let showFindInDocument = Notification.Name("showFindInDocument")
    static let showReplaceInDocument = Notification.Name("showReplaceInDocument")
    static let copyInTerminal = Notification.Name("copyInTerminal")
    static let pasteInTerminal = Notification.Name("pasteInTerminal")
    static let acpStoreRemoved = Notification.Name("acpStoreRemoved")
    static let exportDiagnostics = Notification.Name("exportDiagnostics")
    static let spotlightRestoreRequested = Notification.Name("spotlightRestoreRequested")
    static let openNewBrowserRequested = Notification.Name("openNewBrowserRequested")
    static let closeBrowserRequested = Notification.Name("closeBrowserRequested")
    static let vibespaceShortcutsDidChange = Notification.Name("vibespaceShortcutsDidChange")
    static let focusProjectByNumber = Notification.Name("focusProjectByNumber")
    static let focusNextProject = Notification.Name("focusNextProject")
    static let focusPreviousProject = Notification.Name("focusPreviousProject")
    static let focusNextProjectTerminal = Notification.Name("focusNextProjectTerminal")
    static let focusPreviousProjectTerminal = Notification.Name("focusPreviousProjectTerminal")
    static let openDetailedVibeSpaceView = Notification.Name("openDetailedVibeSpaceView")
    static let openTerminalOnlyVibeSpaceView = Notification.Name("openTerminalOnlyVibeSpaceView")
    static let openAppSettings = Notification.Name("openAppSettings")
    static let openDeveloperTools = Notification.Name("openDeveloperTools")
    static let openAllComments = Notification.Name("openAllComments")
    static let boardNavigateLeft = Notification.Name("boardNavigateLeft")
    static let boardNavigateRight = Notification.Name("boardNavigateRight")
    /// F048-R13: posted when the user invokes the bulk-move keyboard shortcut.
    /// userInfo: ["sourceSurfaceID": UUID]. Listener moves all of the focused
    /// project's tiles from `sourceSurfaceID` to a new detached board window.
    /// No-op outside terminal-board mode (F048-R14).
    static let boardMoveProjectToNewWindowRequested = Notification.Name("boardMoveProjectToNewWindowRequested")
    /// F048-R16: posted when the user invokes the bulk-recall keyboard shortcut.
    /// userInfo: ["sourceSurfaceID": UUID]. Listener moves all tiles on the
    /// detached surface back to the primary surface and closes the now-empty
    /// detached window. No-op when invoked from a primary surface.
    static let boardRecallProjectFromWindowRequested = Notification.Name("boardRecallProjectFromWindowRequested")
    static let checkForAppUpdates = Notification.Name("checkForAppUpdates")
    static let openExternalPaths = Notification.Name("openExternalPaths")
    static let toggleVibeCast = Notification.Name("toggleVibeCast")
    static let toggleTodos = Notification.Name("toggleTodos")
    static let openVibeLanes = Notification.Name("openVibeLanes")
    static let quickCaptureTodo = Notification.Name("quickCaptureTodo")
    /// F052: posted by the title-bar "New Whiteboard" control. Listeners create
    /// an empty `.excalidraw` in the focused project and open it.
    static let newWhiteboard = Notification.Name("newWhiteboard")
    /// F052: posted when a Shelf item is dropped onto a project's file tree.
    /// userInfo: `["sourcePath": String, "targetDirectory": URL]`.
    static let shelfFileMoveToProjectRequested = Notification.Name("shelfFileMoveToProjectRequested")
    static let addACPTileToBoard = Notification.Name("addACPTileToBoard")
    /// Posted by the title-bar New Terminal popover. Listeners create a
    /// terminal in the supplied directory: a board tile in terminal-board
    /// mode, or a temporary spotlight terminal in detailed mode.
    /// userInfo: `[AppCommandUserInfoKey.currentDirectoryURL: URL]` (required),
    /// `[AppCommandUserInfoKey.projectPath: String]` (optional — owning
    /// project root path when the directory belongs to one of the open
    /// projects), `[AppCommandUserInfoKey.preferTemporary: Bool]` (optional —
    /// when true, force a temporary spotlight terminal even in board mode).
    static let createTerminalRequested = Notification.Name("createTerminalRequested")
    static let terminalShortcutStoreDidChange = Notification.Name("TerminalShortcutStore.didChange")
    static let ghosttyOpenLinkTargetRequested = Notification.Name("ghosttyOpenLinkTargetRequested")
    static let ghosttyOpenFileSystemTargetRequested = Notification.Name("ghosttyOpenFileSystemTargetRequested")
    static let terminalAddFileToShelfRequested = Notification.Name("terminalAddFileToShelfRequested")
    static let fileSystemContentsDidChange = Notification.Name("fileSystemContentsDidChange")
    /// F021-R15 / R16 / R17: posted by `EditorGroupStore.activateTab` whenever a
    /// tab becomes active (user-initiated or programmatic). Listeners may resolve
    /// the active tab's owning project and switch focus accordingly. Idempotent
    /// when the resolved project is already focused.
    /// userInfo: `[AppCommandUserInfoKey.tab: ContentViewerTab]`.
    static let contentViewerTabActivated = Notification.Name("contentViewerTabActivated")
    /// F021-R17: posted by `VibeSpaceTerminalBoardStore.activateTile` when a
    /// board tile becomes active. Listeners resolve the project from the path
    /// and switch focus. Idempotent.
    /// userInfo: `[AppCommandUserInfoKey.projectPath: String]` (key omitted when
    /// the tile has no project association).
    static let boardTileActivated = Notification.Name("boardTileActivated")
    /// F021-R13: posted when the user selects "Park Project" from a context menu.
    /// userInfo: `[AppCommandUserInfoKey.projectID: UUID]`.
    static let parkProjectRequested = Notification.Name("parkProjectRequested")
    /// F021-R13: posted when the user selects "Activate Project" on a parked
    /// project.
    /// userInfo: `[AppCommandUserInfoKey.projectPath: String]`.
    static let activateProjectRequested = Notification.Name("activateProjectRequested")
    /// F021-R18: posted when the user selects "Remove Project" on a live
    /// (active) project context menu.
    /// userInfo: `[AppCommandUserInfoKey.projectID: UUID]`.
    static let removeProjectRequested = Notification.Name("removeProjectRequested")
    /// F021-R19: posted when the user selects "Remove Project" on a parked
    /// project context menu.
    /// userInfo: `[AppCommandUserInfoKey.projectPath: String]`.
    static let removeParkedProjectRequested = Notification.Name("removeParkedProjectRequested")
    /// F055: posted after a git worktree is deleted so the unified sidebar
    /// re-discovers worktrees (covers not-added worktrees whose removal doesn't
    /// change the project set).
    static let vibespaceWorktreesDidChange = Notification.Name("vibespaceWorktreesDidChange")
}

enum AppCommandUserInfoKey {
    static let source = "source"
    static let index = "index"
    static let url = "url"
    static let currentDirectoryURL = "currentDirectoryURL"
    static let sessionID = "sessionID"
    static let line = "line"
    static let column = "column"
    static let sourceSurfaceID = "sourceSurfaceID"
    static let tab = "tab"
    static let projectPath = "projectPath"
    static let projectID = "projectID"
    static let preferTemporary = "preferTemporary"
}

enum AppCommandSource {
    static let menu = "menu"
    static let settings = "settings"
}

private struct CoreMenuPruningCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {}
        CommandGroup(replacing: .appSettings) {}
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
    }
}

private struct SecondaryMenuPruningCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .windowArrangement) {}
        CommandGroup(replacing: .windowSize) {}
        CommandGroup(replacing: .windowList) {}
    }
}

private struct OptionsMenuCommands: Commands {
    let appName: String

    var body: some Commands {
        CommandMenu("Options") {
            Button("About \(appName)") {
                NSApp.orderFrontStandardAboutPanel(nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Check for Updates…") {
                NotificationCenter.default.post(
                    name: .checkForAppUpdates,
                    object: nil,
                    userInfo: [AppCommandUserInfoKey.source: AppCommandSource.menu]
                )
            }

            Divider()

            Button("Settings…") {
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            }

            Button("Vibe Lanes") {
                NotificationCenter.default.post(name: .openVibeLanes, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Developer Tools") {
                NotificationCenter.default.post(name: .openDeveloperTools, object: nil)
            }

            Divider()

            Button("All Comments in Vibespace") {
                NotificationCenter.default.post(name: .openAllComments, object: nil)
            }
        }
    }
}

private struct HelpLinksCommands: Commands {
    private let websiteURL = URL(string: "https://crispyvibe.com")!
    private let xURL = URL(string: "https://x.com/Crispy")!
    private let youtubeURL = URL(string: "https://www.youtube.com/@Crispy")!
    private let linkedinGroupURL = URL(string: "https://www.linkedin.com/groups/18621081/")!
    private let authorWebsiteURL = URL(string: "https://manumishra.com")!
    private let authorXURL = URL(string: "https://x.com/MrManuMishra")!
    private let authorLinkedInURL = URL(string: "https://www.linkedin.com/in/manu-mishra/")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Crispy Website") {
                NSWorkspace.shared.open(websiteURL)
            }

            Button("Crispy on X") {
                NSWorkspace.shared.open(xURL)
            }

            Button("YouTube Channel") {
                NSWorkspace.shared.open(youtubeURL)
            }

            Button("LinkedIn Group") {
                NSWorkspace.shared.open(linkedinGroupURL)
            }

            Divider()

            Button("Meet the Author") {
                NSWorkspace.shared.open(authorWebsiteURL)
            }

            Button("Author on X") {
                NSWorkspace.shared.open(authorXURL)
            }

            Button("Author on LinkedIn") {
                NSWorkspace.shared.open(authorLinkedInURL)
            }
        }
    }
}

@MainActor
@main
struct CrispyVibesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appName = "Crispy"
    private let appContainer: AppContainer

    init() {
        let appContainer = AppContainer.makeDefault(resumeVibeLaneTasks: !Self.isRunningUnitTests)
        self.appContainer = appContainer
        appDelegate.appContainer = appContainer
        if PaneWorkerBootstrap.runIfNeeded() {
            Foundation.exit(EXIT_SUCCESS)
        }
        let terminalBoardStandaloneRegistry = appContainer.terminalBoardStandaloneRegistry
        appContainer.terminalServices.diagnosticsSnapshot.boardStandaloneViewModelCountProvider = {
            terminalBoardStandaloneRegistry.registeredCount
        }
        if !Self.isRunningUnitTests {
            appContainer.agentConversationStore.start()
        }
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        Window("Crispy", id: "main") {
            RootView(appContainer: appContainer)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CoreMenuPruningCommands()
            SecondaryMenuPruningCommands()
            OptionsMenuCommands(appName: appName)
            HelpLinksCommands()
        }

        Window("Developer Tools", id: "developer-tools") {
            DeveloperToolsView(
                metricsStore: appContainer.operationMetricsStore,
                diagnosticsSnapshot: appContainer.terminalServices.diagnosticsSnapshot,
                acpObservabilityStore: appContainer.acpObservabilityStore,
                experimentalFeatures: appContainer.experimentalFeatures,
                acpVibeSpaceContextStore: appContainer.acpVibeSpaceContextStore,
                acpDeveloperToolsService: appContainer.acpDeveloperToolsService,
                contextSummaryObservabilityStore: appContainer.contextSummaryObservabilityStore
            )
            .frame(minWidth: 600, minHeight: 400)
        }

        // F049-R15: workspace-wide comments view.
        Window("All Comments", id: "all-comments") {
            CrossFileCommentsView(
                store: appContainer.vibespaceCommentStore,
                onNavigateFile: { filePath, threadID in
                    NotificationCenter.default.post(
                        name: .commentsNavigateToThread,
                        object: nil,
                        userInfo: ["filePath": filePath, "threadID": threadID]
                    )
                },
                onNavigateBrowser: { url, threadID in
                    NotificationCenter.default.post(
                        name: .commentsNavigateToBrowserURL,
                        object: nil,
                        userInfo: ["url": url, "threadID": threadID]
                    )
                }
            )
            .frame(minWidth: 540, minHeight: 480)
        }
    }
}
