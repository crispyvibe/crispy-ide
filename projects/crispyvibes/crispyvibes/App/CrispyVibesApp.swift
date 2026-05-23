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
    static let boardNavigateLeft = Notification.Name("boardNavigateLeft")
    static let boardNavigateRight = Notification.Name("boardNavigateRight")
    static let checkForAppUpdates = Notification.Name("checkForAppUpdates")
    static let openExternalPaths = Notification.Name("openExternalPaths")
    static let toggleVibeCast = Notification.Name("toggleVibeCast")
    static let addACPTileToBoard = Notification.Name("addACPTileToBoard")
    static let terminalShortcutStoreDidChange = Notification.Name("TerminalShortcutStore.didChange")
    static let ghosttyOpenLinkTargetRequested = Notification.Name("ghosttyOpenLinkTargetRequested")
    static let ghosttyOpenFileSystemTargetRequested = Notification.Name("ghosttyOpenFileSystemTargetRequested")
    static let terminalAddFileToShelfRequested = Notification.Name("terminalAddFileToShelfRequested")
    static let fileSystemContentsDidChange = Notification.Name("fileSystemContentsDidChange")
    /// F021-R15 / R16 / R17: posted by `EditorGroupStore.activateTab` whenever a
    /// tab becomes active (user-initiated or programmatic). Listeners may resolve
    /// the active tab's owning project and switch focus accordingly. Idempotent
    /// when the resolved project is already focused.
    static let contentViewerTabActivated = Notification.Name("contentViewerTabActivated")
    /// F021-R17: posted by `VibeSpaceTerminalBoardStore.activateTile` when a
    /// board tile becomes active. userInfo: ["projectPath": String?]. Listeners
    /// resolve the project from the path and switch focus. Idempotent.
    static let boardTileActivated = Notification.Name("boardTileActivated")
    /// F021-R13: posted when the user selects "Park Project" from a context menu.
    /// userInfo: ["projectID": UUID].
    static let parkProjectRequested = Notification.Name("parkProjectRequested")
    /// F021-R13: posted when the user selects "Activate Project" on a parked
    /// project. userInfo: ["projectPath": String].
    static let activateProjectRequested = Notification.Name("activateProjectRequested")
}

enum AppCommandUserInfoKey {
    static let source = "source"
    static let index = "index"
    static let url = "url"
    static let currentDirectoryURL = "currentDirectoryURL"
    static let sessionID = "sessionID"
    static let line = "line"
    static let column = "column"
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

            Button("Developer Tools") {
                NotificationCenter.default.post(name: .openDeveloperTools, object: nil)
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
        let appContainer = AppContainer.makeDefault()
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
                acpDeveloperToolsService: appContainer.acpDeveloperToolsService
            )
            .frame(minWidth: 600, minHeight: 400)
        }
    }
}
