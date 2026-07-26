import AppKit
import CoreServices
import Foundation
import Sparkle
import SwiftUI
import os.signpost

@MainActor
enum ExternalOpenRelay {
    struct Request {
        let urls: [URL]
        let preferTerminal: Bool
    }

    private static var queuedRequests: [Request] = []

    static func submit(_ request: Request) {
        queuedRequests.append(request)
        postPendingRequestsNotification()
    }

    static func drain() -> [Request] {
        defer { queuedRequests.removeAll() }
        return queuedRequests
    }

    private static func postPendingRequestsNotification() {
        NotificationCenter.default.post(
            name: .openExternalPaths,
            object: nil
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var appContainer: AppContainer?
    /// F051: owns the remote-CLI exec relay lifecycle.
    @MainActor var cliExecRelayServer: CLIExecRelayServer?
    static let infoPlistEnableSparkleUpdaterKey = "CrispyVibesEnableSparkleUpdater"

    @objc func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://crispyvibe.com")!)
    }

    static let forwardedExternalOpenNotificationName = Notification.Name("CrispyVibesForwardedExternalOpen")
    static let forwardedExternalOpenPathsKey = "paths"
    static let forwardedExternalOpenSenderPIDKey = "senderPID"

    static var isSparkleUpdaterEnabled: Bool {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: infoPlistEnableSparkleUpdaterKey) else {
            return true
        }
        if let enabled = rawValue as? Bool {
            return enabled
        }
        if let stringValue = rawValue as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "0", "false", "no":
                return false
            case "1", "true", "yes":
                return true
            default:
                return true
            }
        }
        return true
    }

    lazy var textProcessorService = TextProcessorService()
    lazy var sparkleUpdaterController: SPUStandardUpdaterController? = {
        guard Self.isSparkleUpdaterEnabled else { return nil }
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()
    lazy var logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
        category: "services"
    )
    lazy var brandingAccessoryIdentifier = NSUserInterfaceItemIdentifier(
        "\(Bundle.main.bundleIdentifier ?? "com.crispyvibe.app").titlebar.branding"
    )
    var windowObservers: [NSObjectProtocol] = []
    var distributedThemeObserver: NSObjectProtocol?
    var distributedExternalOpenObserver: NSObjectProtocol?
    var keyboardShortcutMonitor: Any?
    var lastObservedAppearancePreference = AppPreferences.defaultAppearancePreference
    var lastObservedThemePreset = AppPreferences.defaultAppThemePreset
    var lastObservedCustomThemeJSON = ""
    var lastObservedAutoUpdateChecksEnabled = AppPreferences.defaultAutoUpdateChecksEnabled
    var lastObservedAppUpdateFeedURL = AppPreferences.defaultAppUpdateFeedURL
    var lastObservedCodeFontSize = AppPreferences.defaultCodeFontSize

    var serviceProviderName: String {
        Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
    }

    var isPaneWorkerProcess: Bool {
        PaneWorkerBootstrap.isPaneTaskProcess
    }

    /// Skips launch side effects under XCTest. Stored (not computed) so tests
    /// that exercise the launch path itself can opt back in.
    var isRunningUnitTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    deinit {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let distributedThemeObserver {
            DistributedNotificationCenter.default().removeObserver(distributedThemeObserver)
        }
        if let distributedExternalOpenObserver {
            DistributedNotificationCenter.default().removeObserver(distributedExternalOpenObserver)
        }
        if let keyboardShortcutMonitor {
            NSEvent.removeMonitor(keyboardShortcutMonitor)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isRunningUnitTests else { return }
        guard !isPaneWorkerProcess else { return }
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.servicesProvider = textProcessorService
        NSRegisterServicesProvider(textProcessorService, serviceProviderName)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningUnitTests else { return }
        guard !isPaneWorkerProcess else { return }
        AppPreferences.migrateUserDefaultsIfNeeded()
        if AppInstallationGuard.handleLaunchIfNeeded() {
            return
        }
        NSApp.servicesProvider = textProcessorService
        NSUpdateDynamicServices()
        registerCurrentBundleWithLaunchServices()
        configureForwardedExternalOpenObserver()
        applyBundleConfiguredApplicationIcon()
        let defaults = UserDefaults.standard
        lastObservedAppearancePreference = defaults.string(forKey: AppPreferences.appearancePreferenceKey)
            ?? AppPreferences.defaultAppearancePreference
        lastObservedThemePreset = defaults.string(forKey: AppPreferences.appThemePresetKey)
            ?? AppPreferences.defaultAppThemePreset
        lastObservedCustomThemeJSON = defaults.string(forKey: AppPreferences.appCustomThemePaletteJSONKey)
            ?? ""
        lastObservedAutoUpdateChecksEnabled = AppPreferences.autoUpdateChecksEnabled(
            userDefaults: defaults
        )
        lastObservedAppUpdateFeedURL = Self.normalizedAppUpdateFeedURL(userDefaults: defaults)
        lastObservedCodeFontSize = Double(AppPreferences.codeFontSize(userDefaults: defaults))
        let rephraseSelector = NSSelectorFromString("rephrase:userData:error:")
        let researchSelector = NSSelectorFromString("research:userData:error:")
        logger.info(
            "Services registered: provider=\(NSStringFromClass(type(of: self.textProcessorService)), privacy: .public) rephrase=\(self.textProcessorService.responds(to: rephraseSelector)) research=\(self.textProcessorService.responds(to: researchSelector))"
        )
        configureKeyboardShortcuts()
        configureWindowChromeObservers()
        configureSparkleUpdater(
            autoChecksEnabled: lastObservedAutoUpdateChecksEnabled,
            feedURLString: lastObservedAppUpdateFeedURL,
            shouldResetCycle: true
        )
        startAgentCLISocketServerIfEnabled()
        DispatchQueue.main.async { [weak self] in
            self?.applyWindowChromeToAllWindows()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isRunningUnitTests else { return }
        guard !isPaneWorkerProcess else { return }
        // Self-heal: if the Agent CLI listener died (e.g. a fatal accept error
        // left the socket orphaned), this rebinds it. No-op when already
        // serving, since start() guards on the running flag.
        startAgentCLISocketServerIfEnabled()
        appContainer?.vibeLoopScheduler.reconcileNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isPaneWorkerProcess else { return }
        MainActor.assumeIsolated {
            appContainer?.terminalBoardDetachedWindowManager.closeAll()
            appContainer?.terminalBoardStandaloneRegistry.shutdownAll()
            appContainer?.vibeLoopScheduler.shutdown()
            appContainer?.vibeLoopManager.shutdown()
            appContainer?.automationBootstrapCoordinator.shutdown()
            appContainer?.vibeLaneTaskManager.shutdown()
            appContainer?.cliSocketServer.shutdown()
            cliExecRelayServer?.shutdown()
            appContainer?.jupyterServerService.shutdownAll()
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let urls = normalizedExistingExternalURLs(
            from: [URL(fileURLWithPath: filename)]
        )
        guard !urls.isEmpty else { return false }
        dispatchExternalOpen(urls: urls)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let normalizedURLs = normalizedExistingExternalURLs(from: urls)
        guard !normalizedURLs.isEmpty else { return }
        dispatchExternalOpen(urls: normalizedURLs)
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = normalizedExistingExternalURLs(
            from: filenames.map { URL(fileURLWithPath: $0) }
        )
        guard !urls.isEmpty else {
            application.reply(toOpenOrPrint: .failure)
            return
        }
        dispatchExternalOpen(urls: urls)
        application.reply(toOpenOrPrint: .success)
    }

    private func dispatchExternalOpen(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if forwardExternalOpenToPrimaryInstanceIfNeeded(urls: urls) {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }
        submitExternalOpenLocally(urls: urls)
    }

    private func configureKeyboardShortcuts() {
        guard keyboardShortcutMonitor == nil else { return }
        keyboardShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyboardShortcut(event) ? nil : event
        }
    }

    @MainActor
    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        guard let action = AppShortcutRegistry.action(matching: event) else {
            return false
        }
        let firstResponder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder ?? NSApp.mainWindow?.firstResponder
        let binding = AppShortcutRegistry.binding(for: action)
        guard AppShortcutRouting.shouldInterceptAppShortcut(binding: binding, firstResponder: firstResponder) else {
            return false
        }
        dispatchShortcutAction(action)
        return true
    }

    @MainActor
    private func dispatchShortcutAction(_ action: AppShortcutAction) {
        switch action {
        case .saveDocument:
            NotificationCenter.default.post(name: .saveCurrentMarkdown, object: nil)
        case .findInDocument:
            NotificationCenter.default.post(name: .showFindInDocument, object: nil)
        case .replaceInDocument:
            NotificationCenter.default.post(name: .showReplaceInDocument, object: nil)
        case .openDetailedVibeSpaceView:
            NotificationCenter.default.post(name: .openDetailedVibeSpaceView, object: nil)
        case .openTerminalOnlyVibeSpaceView:
            NotificationCenter.default.post(name: .openTerminalOnlyVibeSpaceView, object: nil)
        case .toggleVibeCast:
            NotificationCenter.default.post(name: .toggleVibeCast, object: nil)
        case .quickCaptureTodo:
            NotificationCenter.default.post(name: .quickCaptureTodo, object: nil)
        case .focusNextProject:
            NotificationCenter.default.post(name: .focusNextProject, object: nil)
        case .focusPreviousProject:
            NotificationCenter.default.post(name: .focusPreviousProject, object: nil)
        case .focusProject1:
            postFocusProjectShortcut(1)
        case .focusProject2:
            postFocusProjectShortcut(2)
        case .focusProject3:
            postFocusProjectShortcut(3)
        case .focusProject4:
            postFocusProjectShortcut(4)
        case .focusProject5:
            postFocusProjectShortcut(5)
        case .focusProject6:
            postFocusProjectShortcut(6)
        case .focusProject7:
            postFocusProjectShortcut(7)
        case .focusProject8:
            postFocusProjectShortcut(8)
        case .focusProject9:
            postFocusProjectShortcut(9)
        case .focusNextProjectTerminal:
            NotificationCenter.default.post(name: .focusNextProjectTerminal, object: nil)
        case .focusPreviousProjectTerminal:
            NotificationCenter.default.post(name: .focusPreviousProjectTerminal, object: nil)
        case .boardNavigateLeft:
            NotificationCenter.default.post(name: .boardNavigateLeft, object: nil)
        case .boardNavigateRight:
            NotificationCenter.default.post(name: .boardNavigateRight, object: nil)
        case .boardMoveProjectToNewWindow:
            postBoardBulkMoveShortcut(.boardMoveProjectToNewWindowRequested)
        case .boardRecallProjectFromWindow:
            postBoardBulkMoveShortcut(.boardRecallProjectFromWindowRequested)
        case .increaseFontSize:
            adjustCodeFontSize(by: 1)
        case .decreaseFontSize:
            adjustCodeFontSize(by: -1)
        case .resetFontSize:
            UserDefaults.standard.set(
                AppPreferences.defaultCodeFontSize,
                forKey: AppPreferences.codeFontSizeKey
            )
        case .openSettings:
            NotificationCenter.default.post(name: .openAppSettings, object: nil)
        case .openDeveloperTools:
            NotificationCenter.default.post(name: .openDeveloperTools, object: nil)
        }
    }

    private func postFocusProjectShortcut(_ index: Int) {
        NotificationCenter.default.post(
            name: .focusProjectByNumber,
            object: nil,
            userInfo: [AppCommandUserInfoKey.index: index]
        )
    }

    /// F048-R13/R16: post a bulk-move/recall notification with the source
    /// surface ID resolved from the current key window.
    ///
    /// If the key window is a managed detached board window, the source surface
    /// is that window's surface. Otherwise (primary vibespace shell or any
    /// other window), the source defaults to the active vibespace's primary
    /// surface — the listener is the one that ultimately checks board mode and
    /// focused project, so we just need a sensible source.
    @MainActor
    private func postBoardBulkMoveShortcut(_ name: Notification.Name) {
        var sourceSurfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
        if let keyWindow = NSApp.keyWindow,
           let context = appContainer?.terminalBoardDetachedWindowManager.surfaceContext(forWindow: keyWindow) {
            sourceSurfaceID = context.surfaceID
        }
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [AppCommandUserInfoKey.sourceSurfaceID: sourceSurfaceID]
        )
    }

    private func adjustCodeFontSize(by delta: Double) {
        let defaults = UserDefaults.standard
        let current = Double(AppPreferences.codeFontSize(userDefaults: defaults))
        let updated = AppPreferences.clampedCodeFontSize(current + delta)
        defaults.set(updated, forKey: AppPreferences.codeFontSizeKey)
    }

    private func submitExternalOpenLocally(urls: [URL]) {
        let preferTerminal = urls.allSatisfy { url in
            let ext = url.pathExtension.lowercased()
            return ext == "sh"
                || ext == "zsh"
                || ext == "bash"
                || ext == "fish"
                || ext == "command"
        }

        DispatchQueue.main.async {
            ExternalOpenRelay.submit(
                .init(
                    urls: urls,
                    preferTerminal: preferTerminal
                )
            )
            self.focusPrimaryWindow()
        }
    }

    private func forwardExternalOpenToPrimaryInstanceIfNeeded(urls: [URL]) -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let primaryInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { app in
                app.processIdentifier != currentPID && !app.isTerminated && app.processIdentifier < currentPID
            }
            .min(by: { $0.processIdentifier < $1.processIdentifier })

        guard let primaryInstance else { return false }

        DistributedNotificationCenter.default().post(
            name: Self.forwardedExternalOpenNotificationName,
            object: bundleIdentifier,
            userInfo: [
                Self.forwardedExternalOpenPathsKey: urls.map(\.path),
                Self.forwardedExternalOpenSenderPIDKey: currentPID,
            ]
        )
        primaryInstance.activate(options: [.activateAllWindows])
        return true
    }

    private func configureForwardedExternalOpenObserver() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        distributedExternalOpenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.forwardedExternalOpenNotificationName,
            object: bundleIdentifier,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let senderPID = notification.userInfo?[Self.forwardedExternalOpenSenderPIDKey] as? Int32
            guard senderPID != ProcessInfo.processInfo.processIdentifier else { return }
            let paths = notification.userInfo?[Self.forwardedExternalOpenPathsKey] as? [String] ?? []
            let urls = self.normalizedExistingExternalURLs(
                from: paths.map { URL(fileURLWithPath: $0) }
            )
            guard !urls.isEmpty else { return }
            self.submitExternalOpenLocally(urls: urls)
        }
    }

    private func normalizedExistingExternalURLs(from urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var normalizedURLs: [URL] = []
        normalizedURLs.reserveCapacity(urls.count)

        for url in urls {
            let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
            let normalized = fileURL.standardizedFileURL
            guard FileManager.default.fileExists(atPath: normalized.path) else { continue }
            guard seenPaths.insert(normalized.path).inserted else { continue }
            normalizedURLs.append(normalized)
        }

        return normalizedURLs
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        focusPrimaryWindow()
        return false
    }

    @MainActor
    private func focusPrimaryWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func registerCurrentBundleWithLaunchServices() {
        let status = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        guard status != noErr else { return }
        logger.error("LaunchServices registration failed with status \(status, privacy: .public)")
    }
}
