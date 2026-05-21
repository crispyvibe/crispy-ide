import AppKit
import Foundation
import GhosttyKit

@MainActor
extension GhosttyTerminalEngine {
    func handleRendererHealth(_ health: ghostty_action_renderer_health_e) {
        guard health == GHOSTTY_RENDERER_HEALTH_UNHEALTHY else { return }
        scheduleRendererRecovery(reason: .rendererUnhealthy, delay: 0.0)
    }

    func recoverSurfaceAfterRendererFailure(reason: TerminalLifecycleReason) {
        guard started else { return }

        if surface == nil {
            terminalView.createSurfaceIfNeeded()
            return
        }

        guard let surface else { return }
        terminalView.applyCurrentDisplayIDIfAvailable()
        terminalView.syncSurfaceGeometry()
        applyColorSchemePreference()
        if let runtimeConfig {
            ghostty_surface_update_config(surface, runtimeConfig)
        } else {
            applyThemeOverrideIfPossible()
        }
        applyFontSizeToSurface()
        terminalView.updateMarkedTextInSurface()

        if terminalView.window != nil, started {
            resumeAppropriateOutputPolling()
        } else {
            stopOutputPolling()
        }
        if let sid = sessionID {
            terminalServices.diagnosticsSnapshot.update(sessionID: sid) { $0.isOccluded = false }
        }

        if terminalView.window?.firstResponder === terminalView {
            ghostty_surface_set_focus(surface, true)
        } else {
            ghostty_surface_set_focus(surface, false)
        }

        ghostty_surface_refresh(surface)
        captureVisibleContentsIfNeeded()

        TerminalLifecycleLogger.log(
            event: .surfaceResize,
            sessionDebugID: sessionDebugID,
            surfaceDebugID: surfaceDebugID,
            sessionID: sessionID,
            reason: reason,
            extra: ["recovered": "true"]
        )
    }

    func scheduleRendererRecovery(
        reason: TerminalLifecycleReason,
        delay: TimeInterval
    ) {
        pendingRendererRecoveryWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRendererRecoveryWorkItem = nil
            self.recoverSurfaceAfterRendererFailure(reason: reason)
        }

        pendingRendererRecoveryWorkItem = workItem
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func currentDimensions() -> (cols: Int, rows: Int) {
        guard let surface else {
            return (preferredColumns, preferredRows)
        }
        let size = ghostty_surface_size(surface)
        return (Int(size.columns), Int(size.rows))
    }

    func resize(cols: Int, rows: Int) {
        preferredColumns = cols
        preferredRows = rows
        terminalView.setDesiredGridSize(columns: cols, rows: rows, font: font)
    }

    func applyThemePalette(_ palette: AppThemePalette) {
        currentPalette = palette
        terminalView.overrideBackgroundColor = palette.canvasBackground.nsColor
        applyColorSchemePreference()
        applyThemeOverrideIfPossible()
    }

    func setSurfaceFocus(_ focused: Bool) {
        guard let surface = terminalView.surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    func applyFontSizeToSurface() {
        guard let surface else { return }
        let action = "set_font_size:\(Int(font.pointSize))"
        action.withCString { pointer in
            _ = ghostty_surface_binding_action(surface, pointer, UInt(strlen(pointer)))
        }
    }

    func applyColorSchemePreference() {
        let scheme: ghostty_color_scheme_e =
            terminalView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? GHOSTTY_COLOR_SCHEME_DARK
            : GHOSTTY_COLOR_SCHEME_LIGHT
        if let surface {
            ghostty_surface_set_color_scheme(surface, scheme)
        } else if let app = terminalServices.ghosttyRuntime.app {
            ghostty_app_set_color_scheme(app, scheme)
        }
    }

    func applyThemeOverrideIfPossible() {
        if let runtimeConfig {
            ghostty_config_free(runtimeConfig)
            self.runtimeConfig = nil
        }

        guard let config = ghostty_config_new() else { return }
        ghostty_config_load_default_files(config)

        let configContents = GhosttyTerminalEngineSupport.runtimeConfigContents(
            for: currentPalette,
            historySize: historySize,
            columns: preferredColumns,
            rows: preferredRows
        )
        do {
            try configContents.write(
                to: runtimeConfigURL,
                atomically: true,
                encoding: String.Encoding.utf8
            )
        } catch {
            ghostty_config_free(config)
            return
        }

        runtimeConfigURL.path.withCString { configPath in
            ghostty_config_load_file(config, configPath)
        }
        ghostty_config_finalize(config)
        runtimeConfig = config

        if let surface {
            ghostty_surface_update_config(surface, config)
            ghostty_surface_refresh(surface)
        }
    }
}
