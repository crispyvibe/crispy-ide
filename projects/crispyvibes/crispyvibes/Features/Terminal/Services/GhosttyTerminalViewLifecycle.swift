
import AppKit
import Foundation
import GhosttyKit
import QuartzCore

@MainActor
extension GhosttyTerminalView {
    func syncBackingLayerMetrics(pixelWidth: UInt32, pixelHeight: UInt32, backingScale: Double) {
        let layerScale = CGFloat(max(backingScale, 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window?.backingScaleFactor ?? layerScale
        CATransaction.commit()

        if let metalLayer = layer as? CAMetalLayer {
            let drawableSize = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
            if metalLayer.drawableSize != drawableSize {
                metalLayer.drawableSize = drawableSize
            }
        }
    }

    func handleScreenChangeBackingRefresh() {
        guard window != nil else { return }
        syncSurfaceGeometry(force: true)
        inputContext?.invalidateCharacterCoordinates()
        onWindowScreenChangeHandledForTesting?()
    }

    func updateScreenChangeObservation(for window: NSWindow?) {
        guard observedWindowForScreenChanges !== window else { return }

        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }

        observedWindowForScreenChanges = window

        guard let window else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWindowDidChangeScreen()
            }
        }
    }

    func handleWindowDidChangeScreen() {
        guard window != nil else { return }
        applyCurrentDisplayIDIfAvailable()
        DispatchQueue.main.async { [weak self] in
            self?.handleScreenChangeBackingRefresh()
        }
    }

    func applyCurrentDisplayIDIfAvailable() {
        guard let surface else { return }
        guard let displayID = window?.screen?.crispyvibesDisplayID, displayID != 0 else { return }
        ghostty_surface_set_display_id(surface, displayID)
    }

    func createSurfaceIfNeeded() {
        guard surface == nil else { return }
        guard let engine, let app = engine.terminalServices.ghosttyRuntime.app else { return }
        guard engine.canCreateSurface else { return }
        guard window != nil else { return }
        let callbackContextPointer = ensureSurfaceCallbackContext()

        let command = engine.launchCommand
        let initialInput = engine.initialSurfaceInput
        let directory = engine.launchWorkingDirectory.path
        let environment = engine.launchEnvironmentDictionary
        let scale = Double(crispyvibesBackingScaleFactor())
        let fontSize = Float(engine.font.pointSize)
        var envStorage: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = []
        var envValues = [ghostty_env_var_s]()
        defer {
            for (key, value) in envStorage {
                free(key)
                free(value)
            }
        }

        for (key, value) in environment {
            guard let keyDup = strdup(key), let valueDup = strdup(value) else { continue }
            envStorage.append((keyDup, valueDup))
            envValues.append(ghostty_env_var_s(key: keyDup, value: valueDup))
        }

        directory.withCString { cwdPointer in
            var config = ghostty_surface_config_new()
            config.platform_tag = GHOSTTY_PLATFORM_MACOS
            config.platform = ghostty_platform_u(
                macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())
            )
            config.userdata = callbackContextPointer
            config.scale_factor = scale
            config.font_size = fontSize
            config.working_directory = cwdPointer
            config.env_var_count = envValues.count
            config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

            let createSurface = { [self] in
                envValues.withUnsafeMutableBufferPointer { buffer in
                    config.env_vars = buffer.baseAddress
                    self.surface = ghostty_surface_new(app, &config)
                }
            }

            let createWithInitialInput = { (commandPointer: UnsafePointer<CChar>?) in
                config.command = commandPointer
                if let initialInput, !initialInput.isEmpty {
                    initialInput.withCString { inputPointer in
                        config.initial_input = inputPointer
                        createSurface()
                    }
                } else {
                    config.initial_input = nil
                    createSurface()
                }
            }

            if let command, !command.isEmpty {
                command.withCString { commandPointer in
                    createWithInitialInput(commandPointer)
                }
            } else {
                createWithInitialInput(nil)
            }
        }

        guard let surface else { return }
        applyCurrentDisplayIDIfAvailable()
        lastSyncedSurfaceGeometry = nil
        syncSurfaceGeometry()
        updateMarkedTextInSurface()
        if window?.firstResponder === self, let sessionID = engine.sessionID {
            engine.terminalServices.focusCoordinator.focus(engine: engine, sessionID: sessionID)
        } else {
            ghostty_surface_set_focus(surface, false)
        }

        let newDebugID = TerminalDebugID.nextSurface()
        engine.surfaceDebugID = newDebugID
        if let sid = engine.sessionID {
            engine.terminalServices.diagnosticsSnapshot.update(sessionID: sid) { $0.surfaceDebugID = newDebugID }
            engine.terminalServices.diagnosticsSnapshot.recordEvent(sessionID: sid, event: .surfaceCreate)
        }
        TerminalLifecycleLogger.log(
            event: .surfaceCreate,
            sessionDebugID: engine.sessionDebugID,
            surfaceDebugID: newDebugID,
            sessionID: engine.sessionID,
            reason: .initial,
            extra: ["hadSurfaceBefore": "false"]
        )

        engine.handleSurfaceCreated()
    }

    func syncSurfaceGeometry(force: Bool = false) {
        guard let surface else { return }

        let pointsSize: CGSize
        if bounds.width > 0, bounds.height > 0 {
            pointsSize = bounds.size
        } else {
            pointsSize = desiredPixelSize
        }

        let backingRect = convertToBacking(NSRect(origin: .zero, size: pointsSize))
        let pixelWidth = UInt32(max(backingRect.width, 1))
        let pixelHeight = UInt32(max(backingRect.height, 1))
        let scale = Double(crispyvibesBackingScaleFactor())
        let geometry = GhosttyTerminalView.SurfaceGeometry(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            backingScale: scale
        )
        guard force || geometry != lastSyncedSurfaceGeometry else {
            return
        }
        lastSyncedSurfaceGeometry = geometry
        syncBackingLayerMetrics(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            backingScale: scale
        )
        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_size(surface, pixelWidth, pixelHeight)
        if let engine, let sid = engine.sessionID {
            engine.terminalServices.diagnosticsSnapshot.update(sessionID: sid) { $0.pixelWidth = pixelWidth; $0.pixelHeight = pixelHeight }
        }
        TerminalLifecycleLogger.log(
            event: .surfaceResize,
            sessionDebugID: engine?.sessionDebugID,
            surfaceDebugID: engine?.surfaceDebugID,
            sessionID: engine?.sessionID,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            backingScale: scale
        )
        engine?.handleSurfaceSizeDidChange()
    }

    func destroySurface() {
        guard let surface else { return }
        let callbackContextPointer = surfaceCallbackContextPointer
        let sfid = engine?.surfaceDebugID
        TerminalLifecycleLogger.log(
            event: .surfaceDestroy,
            sessionDebugID: engine?.sessionDebugID,
            surfaceDebugID: sfid,
            sessionID: engine?.sessionID,
            reason: .terminate
        )
        if let engine, let sid = engine.sessionID {
            engine.terminalServices.diagnosticsSnapshot.update(sessionID: sid) { $0.surfaceDebugID = nil }
            engine.terminalServices.diagnosticsSnapshot.recordEvent(sessionID: sid, event: .surfaceDestroy)
        }
        engine?.surfaceDebugID = nil
        self.surface = nil
        self.surfaceCallbackContextPointer = nil
        lastSyncedSurfaceGeometry = nil
        Self.freeSurfaceAsync(surface, callbackContextPointer: callbackContextPointer)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScreenChangeObservation(for: window)
        createSurfaceIfNeeded()

        if let engine, let sid = engine.sessionID {
            let visible = window != nil
            engine.terminalServices.diagnosticsSnapshot.update(sessionID: sid) { $0.isVisible = visible }
        }

        applyCurrentDisplayIDIfAvailable()
        syncSurfaceGeometry()
        engine?.syncOutputPollingToVisibility()
    }

    override func layout() {
        super.layout()
        syncSurfaceGeometry()
        inputContext?.invalidateCharacterCoordinates()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyCurrentDisplayIDIfAvailable()
        syncSurfaceGeometry(force: true)
        inputContext?.invalidateCharacterCoordinates()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let engine, let sessionID = engine.sessionID {
            engine.terminalServices.focusCoordinator.focus(engine: engine, sessionID: sessionID)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let engine, let sessionID = engine.sessionID {
            engine.terminalServices.focusCoordinator.relinquish(sessionID: sessionID)
        }
        return result
    }
}
