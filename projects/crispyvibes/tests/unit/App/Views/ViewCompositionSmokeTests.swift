import AppKit
import Foundation
import PDFKit
import SwiftUI
import XCTest
@testable import CrispyVibes

@MainActor
final class ViewCompositionSmokeTests: XCTestCase {
    final class Box<Value> {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    var appStore: AppPersistenceDataStore!
    var container: AppContainer!
    var vibespaceManagement: VibeSpaceManagementService!

    var tempRoot: URL!
    var layoutStateFileURL: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-view-smoke")
        container = AppContainer.makeDefault()
        layoutStateFileURL = tempRoot.appendingPathComponent("layout.json")
        appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        let persistenceStore = VibeSpacePersistenceStore(store: appStore)
        vibespaceManagement = VibeSpaceManagementService(persistenceStore: persistenceStore)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    /// Constructs a `VibeSpaceTerminalBoardStore` for tests that exercise
    /// `VibeSpaceTerminalOnlyView` directly. In production the store is created at
    /// the service layer in `AppContainer.makeContentViewDependencies`; tests build
    /// their own with the same dependencies (`layoutPersistence`,
    /// `terminalBoardStandaloneRegistry`).
    private func makeTestBoardStore(vibespaceID: UUID?) -> VibeSpaceTerminalBoardStore {
        VibeSpaceTerminalBoardStore(
            vibespaceID: vibespaceID,
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry
        )
    }

    func testSettingsScreensComposeWithoutCrashing() {
        let appearance = Box(AppearancePreference.system.rawValue)
        let railFontScale = Box(AppPreferences.defaultRailTerminalFontScale)
        let codeFamily = Box(AppPreferences.defaultCodeFontFamily)
        let codeSize = Box(AppPreferences.defaultCodeFontSize)
        let defaultShell = Box(AppPreferences.defaultTerminalShellPreference)
        let defaultRailPosition = Box(ProjectRailPosition.left)
        let cliProfile = Box(AppPreferences.defaultTextServiceCLIProfile)
        let cliCommand = Box(AppPreferences.defaultTextServiceCLICommand)
        let cliArguments = Box(AppPreferences.defaultTextServiceCLIArguments)
        let passAgentFlag = Box(AppPreferences.defaultTextServicePassAgentFlag)
        let defaultAgent = Box(AppPreferences.defaultTextServiceDefaultAgent)
        let rephrasePrompt = Box(AppPreferences.defaultTextServiceRephrasePrompt)
        let researchPrompt = Box(AppPreferences.defaultTextServiceResearchPrompt)
        let themePreset = Box(AppPreferences.defaultAppThemePreset)
        let customThemeJSON = Box(AppThemePalette.encodeToJSON(.midnightMono))
        let sideMenuDockPosition = Box(AppSideMenuDockPosition.right.rawValue)
        let selectedCategory = Box(AppSettingsCategory.general)
        let authDomain = Box(AppPreferences.defaultAuthCognitoDomain)
        let authClientID = Box(AppPreferences.defaultAuthCognitoMacClientId)
        let autoUpdateChecks = Box(AppPreferences.defaultAutoUpdateChecksEnabled)
        let updateFeed = Box(AppPreferences.defaultAppUpdateFeedURL)

        let appSettingsView = AppSettingsSheetView(
            appearancePreference: binding(appearance),
            railFontScale: binding(railFontScale),
            codeFontFamilyRaw: binding(codeFamily),
            codeFontSize: binding(codeSize),
            defaultTerminalShellRaw: binding(defaultShell),
            defaultRailPosition: binding(defaultRailPosition),
            sideMenuDockPositionRaw: binding(sideMenuDockPosition),
            serviceCLIProfile: binding(cliProfile),
            serviceCLICommand: binding(cliCommand),
            serviceCLIArguments: binding(cliArguments),
            servicePassAgentFlag: binding(passAgentFlag),
            serviceDefaultAgent: binding(defaultAgent),
            serviceRephrasePrompt: binding(rephrasePrompt),
            serviceResearchPrompt: binding(researchPrompt),
            themePreset: binding(themePreset),
            customThemePaletteJSON: binding(customThemeJSON),
            selectedCategory: binding(selectedCategory),
            authCognitoDomain: binding(authDomain),
            authCognitoMacClientId: binding(authClientID),
            autoUpdateChecksEnabled: binding(autoUpdateChecks),
            appUpdateFeedURL: binding(updateFeed),
            onResetLocalState: {},
            onClose: {}
        )

        mount(appSettingsView)
        XCTAssertFalse(String(describing: appSettingsView.body).isEmpty)

        let startupSettings = Box(VibeSpaceStartupSettings.default)
        let selectedVibeSpaceSettingsCategory = Box(VibeSpaceSettingsCategory.vibespace)
        let vibespaceDefaultShell = Box(Optional<TerminalShellPreference>.none)
        let sourceControlSettings = Box(VibeSpaceSourceControlSettings.default)
        let vibespaceProjects = [
            VibeSpaceSettingsProjectItem(
                id: UUID(),
                title: "Project A",
                path: "/tmp/project-a",
                shortcutIndex: 1,
                colorTag: ProjectColorTag(red: 0.1, green: 0.2, blue: 0.3)
            ),
            VibeSpaceSettingsProjectItem(
                id: UUID(),
                title: "Project B",
                path: "/tmp/project-b",
                shortcutIndex: nil,
                colorTag: nil
            )
        ]

        let vibespaceSettingsView = VibeSpaceSettingsSheetView(
            vibespaceName: "VibeSpace",
            selectedCategory: binding(selectedVibeSpaceSettingsCategory),
            projects: vibespaceProjects,
            availableTerminalPresets: TerminalViewModel.availableBuiltInPresets(
                using: container.terminalViewModelDependencies
            ),
            availableACPAgents: [],
            startupSettings: binding(startupSettings),
            vibespaceDefaultTerminalShell: binding(vibespaceDefaultShell),
            sourceControlSettings: binding(sourceControlSettings),
            startupOverrideForPath: { _ in nil },
            setStartupOverride: { _, _ in },
            projectACPAgentOverrideIDForPath: { _ in nil },
            setProjectACPAgentOverrideID: { _, _ in },
            setProjectShortcut: { _, _ in },
            projectColorTagForPath: { _ in nil },
            setProjectColorTag: { _, _ in },
            projectTerminalShellOverrideForPath: { _ in nil as TerminalShellPreference? },
            setProjectTerminalShellOverride: { _, _ in },
            onAddProjects: {},
            onAddRemoteProject: {},
            onRemoveProject: { _ in },
            onMoveProjects: { _, _ in },
            onRenameVibeSpace: { _ in },
            onReindexProjects: {},
            onClose: {},
            vibespaceShortcuts: [],
            setVibeSpaceShortcuts: { _ in },
            projectShortcutsForPath: { _ in [] },
            setProjectShortcutsForPath: { _, _ in }
        )

        mount(vibespaceSettingsView)
        XCTAssertFalse(String(describing: vibespaceSettingsView.body).isEmpty)
    }

    func testProjectAndEditorViewsComposeWithoutCrashing() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let markdownFile = projectRoot.appendingPathComponent("notes.md")
        try Data("# Test\n".utf8).write(to: markdownFile)

        let layoutPersistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: layoutStateFileURL
        )
        let project = ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(
                layoutPersistence: layoutPersistence
            )
        )
        let anyProject = AnyProjectSession(project)

        let terminalView = TerminalView(
            viewModel: project.terminalViewModel,
            defaultDirectory: projectRoot
        )
        mount(terminalView)
        XCTAssertFalse(String(describing: terminalView.body).isEmpty)

        let folderExplorerView = FolderExplorerView(
            viewModel: project.folderExplorerViewModel,
            vibespaceInteraction: container.vibespaceInteraction,
            onOpenInTerminal: { _ in }
        )
        mount(folderExplorerView)
        XCTAssertFalse(String(describing: folderExplorerView.body).isEmpty)

        let contentViewerStore = container.makeContentViewerStore()
        contentViewerStore.openFileInTab(at: markdownFile)
        let markdownEditorView = MarkdownEditorView(viewModel: contentViewerStore.markdownViewModel)
        mount(markdownEditorView)
        XCTAssertFalse(String(describing: markdownEditorView.body).isEmpty)

        let focusedView = FocusedProjectView(
            project: anyProject,
            onClose: {},
            projectColorTag: nil,
            onProjectColorTagChanged: { _ in },
            headerCornerRadii: RectangleCornerRadii(
                topLeading: 14,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: 14
            ),
            isTerminalTrayCollapsed: false,
            onToggleTerminalTrayCollapsed: {},
            onTerminalSpotlightRequested: { _ in },
            onTemporaryTerminalRequested: { _ in },
            onTemporaryShortcutRequested: { _, _ in },
            onOpenTerminalInEditorPaneRequested: { _ in },
            onManageShortcutsRequested: {},
            onLinkTargetActivated: { _ in },
            onFileSystemTargetActivated: { _ in }
        )
        mount(focusedView)
        XCTAssertFalse(String(describing: focusedView.body).isEmpty)
    }

    func testWalkthroughOverlayComposesAcrossNavigationStates() {
        struct Provider: FeatureWalkthroughStepProviding {
            let steps: [FeatureWalkthroughStep]
        }

        let suiteName = "walkthrough-smoke-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to initialize isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let steps = [
            FeatureWalkthroughStep(
                id: "one",
                title: "Step One",
                message: "First message",
                heroImageName: "WalkthroughWelcome",
                annotations: [
                    FeatureWalkthroughAnnotation(
                        id: "a",
                        title: "Annotation A",
                        detail: "Detail A",
                        normalizedX: 0.2,
                        normalizedY: 0.3,
                        placement: .topLeading
                    )
                ],
                shortcutHint: "Cmd+1"
            ),
            FeatureWalkthroughStep(
                id: "two",
                title: "Step Two",
                message: "Second message",
                heroImageName: "WalkthroughReady",
                annotations: [
                    FeatureWalkthroughAnnotation(
                        id: "b",
                        title: "Annotation B",
                        detail: "Detail B",
                        normalizedX: 0.7,
                        normalizedY: 0.6,
                        placement: .bottomTrailing
                    )
                ],
                shortcutHint: nil
            )
        ]

        let controller = FeatureWalkthroughController(
            provider: Provider(steps: steps),
            defaults: defaults,
            launchEnvironment: [:],
            completedKey: "walkthrough.completed.smoke"
        )
        controller.presentFromToolbar()

        let overlay = FeatureWalkthroughOverlay(controller: controller)
        mount(overlay)
        XCTAssertFalse(String(describing: overlay.body).isEmpty)
        XCTAssertEqual(controller.progressText, "Step 1 of 2")

        controller.next()
        mount(overlay)
        XCTAssertEqual(controller.progressText, "Step 2 of 2")
        XCTAssertTrue(controller.isLastStep)

        controller.previous()
        XCTAssertEqual(controller.currentStepIndex, 0)
        controller.skip()
        XCTAssertFalse(controller.isPresented)
    }

    func testTerminalOnlyAndStackedProjectViewsComposeWithoutCrashing() throws {
        let projects = try [
            makeProjectSession(rootName: "project-a"),
            makeProjectSession(rootName: "project-b"),
            makeProjectSession(rootName: "project-c")
        ]
        let anyProjects = projects.map(AnyProjectSession.init)
        defer {
            for project in projects {
                for tab in project.terminalViewModel.tabs {
                    project.terminalViewModel.closeTab(tab)
                }
            }
        }

        let emptyView = VibeSpaceTerminalOnlyView(
            vibespaceID: nil,
            projects: [],
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry,
            headerCornerRadii: RectangleCornerRadii(
                topLeading: 14,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: 14
            ),
            onAddProjectsRequested: {},
            onSpotlightRequested: { _, _, _, _, _ in },
            onACPSpotlightRequested: { _, _ in },
            onTemporaryTerminalRequested: { _, _, _, _, _ in },
            onTemporaryShortcutRequested: { _, _, _, _, _, _ in },
            onLinkTargetActivated: { _, _ in },
            onFileSystemTargetActivated: { _, _ in },
            onManageShortcutsRequested: {},
            shortcutDefinitionsForProjectPath: { _ in [] },
            boardStore: makeTestBoardStore(vibespaceID: nil)
        )
        mount(emptyView)
        XCTAssertFalse(String(describing: emptyView.body).isEmpty)

        let populatedVertical = VibeSpaceTerminalOnlyView(
            vibespaceID: UUID(),
            projects: anyProjects,
            projectColorTagsByPath: Dictionary(
                uniqueKeysWithValues: projects.map {
                    ($0.rootURL.standardizedFileURL.path, ProjectColorTag(red: 0.29, green: 0.56, blue: 0.89))
                }
            ),
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry,
            headerCornerRadii: RectangleCornerRadii(
                topLeading: 14,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: 14
            ),
            onAddProjectsRequested: {},
            onSpotlightRequested: { _, _, _, _, _ in },
            onACPSpotlightRequested: { _, _ in },
            onTemporaryTerminalRequested: { _, _, _, _, _ in },
            onTemporaryShortcutRequested: { _, _, _, _, _, _ in },
            onLinkTargetActivated: { _, _ in },
            onFileSystemTargetActivated: { _, _ in },
            onManageShortcutsRequested: {},
            shortcutDefinitionsForProjectPath: { _ in [] },
            boardStore: makeTestBoardStore(vibespaceID: UUID())
        )
        mount(populatedVertical)
        XCTAssertFalse(String(describing: populatedVertical.body).isEmpty)

        let populatedHorizontal = VibeSpaceTerminalOnlyView(
            vibespaceID: UUID(),
            projects: anyProjects,
            layoutPersistence: LayoutPersistenceService(
                fileManager: .default,
                stateFileURL: layoutStateFileURL
            ),
            terminalBoardStandaloneRegistry: container.terminalBoardStandaloneRegistry,
            headerCornerRadii: RectangleCornerRadii(
                topLeading: 14,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: 14
            ),
            onAddProjectsRequested: {},
            onSpotlightRequested: { _, _, _, _, _ in },
            onACPSpotlightRequested: { _, _ in },
            onTemporaryTerminalRequested: { _, _, _, _, _ in },
            onTemporaryShortcutRequested: { _, _, _, _, _, _ in },
            onLinkTargetActivated: { _, _ in },
            onFileSystemTargetActivated: { _, _ in },
            onManageShortcutsRequested: {},
            shortcutDefinitionsForProjectPath: { _ in [] },
            boardStore: makeTestBoardStore(vibespaceID: UUID())
        )
        mount(populatedHorizontal)
        XCTAssertFalse(String(describing: populatedHorizontal.body).isEmpty)

        let terminalTabID = projects[0].terminalViewModel.tabs.first?.id ?? UUID()
        let title = projects[0].terminalViewModel.tabs.first?.title ?? projects[0].title
        let accentColor = ProjectColorTag(storageToken: "#7EDFA6")?.color ?? .green
        let stackedCard = StackedTerminalCardView(
            title: title,
            tabActivityState: projects[0].terminalViewModel.tabActivityStateOrInactive(for: terminalTabID),
            session: projects[0].terminalViewModel.session(for: terminalTabID),
            preferredHeight: 220,
            preferredWidth: 360,
            accentColor: accentColor,
            shortcutIndex: nil,
            onFocus: {},
            onClose: {},
            onHide: {},
            onRestart: {},
            onRename: { _ in },
            onSpotlight: {}
        )
        mount(stackedCard)
        XCTAssertFalse(String(describing: stackedCard.body).isEmpty)
    }
}
