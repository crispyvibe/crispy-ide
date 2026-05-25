import AppKit
import Foundation
import GhosttyKit

extension GhosttyTerminalRuntime {
    func initializeIfNeeded() {
        guard !initialized else { return }
        initialized = true

        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            return
        }

        guard let config = ghostty_config_new() else {
            return
        }
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)
        self.config = config

        var runtimeConfig = ghostty_runtime_config_s()
        let callbackContextPointer = Unmanaged.passRetained(
            GhosttyRuntimeCallbackContext(runtime: self)
        ).toOpaque()
        runtimeConfig.userdata = callbackContextPointer
        self.callbackContextPointer = callbackContextPointer
        runtimeConfig.supports_selection_clipboard = true
        runtimeConfig.wakeup_cb = { userdata in
            let runtime = GhosttyTerminalRuntime.runtime(fromUserdata: userdata)
            GhosttyTerminalRuntime.performOnMainAsync {
                runtime?.tick()
            }
        }
        runtimeConfig.action_cb = { app, target, action in
            if target.tag == GHOSTTY_TARGET_SURFACE {
                if action.tag == GHOSTTY_ACTION_RENDER,
                   let surface = target.target.surface {
                    let engine = GhosttyTerminalRuntime.engine(fromSurface: surface)
                    GhosttyTerminalRuntime.performOnMainAsync {
                        engine?.handleRenderAction()
                    }
                    return true
                }

                if action.tag == GHOSTTY_ACTION_RENDERER_HEALTH,
                   let surface = target.target.surface {
                    let health = action.action.renderer_health
                    let engine = GhosttyTerminalRuntime.engine(fromSurface: surface)
                    GhosttyTerminalRuntime.performOnMainAsync {
                        engine?.handleRendererHealth(health)
                    }
                    return true
                }
            }

            return GhosttyTerminalRuntime.performOnMainSync {
                GhosttyTerminalRuntime.runtime(fromApp: app)?.handleAction(target: target, action: action) ?? false
            }
        }
        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            let engine = GhosttyTerminalRuntime.engine(fromUserdata: userdata)
            let stateBox = UnsafeMutableRawPointerBox(value: state)
            GhosttyTerminalRuntime.performOnMainAsync {
                guard let engine, let surface = engine.surface else { return }
                let value = GhosttyTerminalRuntime.readClipboardString(for: location)
                if !value.isEmpty {
                    (engine.delegate as? TerminalSession)?.insightObserver?.recordTypedKeystroke(value)
                }
                value.withCString { pointer in
                    ghostty_surface_complete_clipboard_request(surface, pointer, stateBox.value, false)
                }
            }
        }
        runtimeConfig.confirm_read_clipboard_cb = { userdata, content, state, _ in
            let engine = GhosttyTerminalRuntime.engine(fromUserdata: userdata)
            let contentBox = UnsafePointerBox<CChar>(value: content)
            let stateBox = UnsafeMutableRawPointerBox(value: state)
            GhosttyTerminalRuntime.performOnMainAsync {
                guard let engine, let surface = engine.surface else { return }
                ghostty_surface_complete_clipboard_request(surface, contentBox.value, stateBox.value, true)
            }
        }
        runtimeConfig.write_clipboard_cb = { _, location, content, len, _ in
            let contentBox = UnsafePointerBox<ghostty_clipboard_content_s>(value: content)
            GhosttyTerminalRuntime.performOnMainAsync {
                guard let content = contentBox.value, len > 0 else { return }
                let buffer = UnsafeBufferPointer(start: content, count: Int(len))
                let text = buffer.compactMap { item -> String? in
                    guard let data = item.data else { return nil }
                    return String(cString: data)
                }.first ?? ""
                GhosttyTerminalRuntime.writeClipboardString(text, for: location)
            }
        }
        runtimeConfig.close_surface_cb = { userdata, processAlive in
            let engine = GhosttyTerminalRuntime.engine(fromUserdata: userdata)
            GhosttyTerminalRuntime.performOnMainAsync {
                guard let engine else { return }
                engine.handleSurfaceClosed(processAlive: processAlive)
            }
        }

        app = ghostty_app_new(&runtimeConfig, config)
    }

    func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE else {
            return false
        }
        guard let engine = Self.engine(fromSurface: target.target.surface) else {
            return false
        }

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            let title = action.action.set_title.title.flatMap { String(cString: $0) } ?? ""
            engine.handleTitleChange(title)
            return true
        case GHOSTTY_ACTION_PWD:
            let directory = action.action.pwd.pwd.flatMap { String(cString: $0) }
            engine.handleWorkingDirectoryChange(directory)
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            let url = decodeUTF8(action.action.open_url.url, count: Int(action.action.open_url.len))
            guard !url.isEmpty else { return false }
            engine.handleOpenURL(url)
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            engine.handleProcessExit(exitCode: Int32(action.action.child_exited.exit_code))
            return true
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            let info = action.action.command_finished
            engine.handleCommandFinished(exitCode: info.exit_code, duration: info.duration)
            return true
        case GHOSTTY_ACTION_RENDER:
            engine.handleRenderAction()
            return true
        default:
            return false
        }
    }

    static func resourceRootURL() -> URL? {
        let bundles = [Bundle.main, Bundle(for: GhosttyTerminalEngine.self)]
        for bundle in bundles {
            guard let root = bundle.resourceURL else { continue }
            let directGhostty = root.appendingPathComponent("ghostty", isDirectory: true)
            if FileManager.default.fileExists(atPath: directGhostty.path) {
                return root
            }
            let nestedRoot = root.appendingPathComponent("GhosttyRuntime", isDirectory: true)
            let nestedGhostty = nestedRoot.appendingPathComponent("ghostty", isDirectory: true)
            if FileManager.default.fileExists(atPath: nestedGhostty.path) {
                return nestedRoot
            }
        }
        return nil
    }

    static func engine(fromSurface surface: ghostty_surface_t?) -> GhosttyTerminalEngine? {
        guard let surface,
              let userdata = ghostty_surface_userdata(surface) else {
            return nil
        }
        return Unmanaged<GhosttySurfaceCallbackContext>.fromOpaque(userdata)
            .takeUnretainedValue()
            .engine
    }

    static func engine(fromUserdata userdata: UnsafeMutableRawPointer?) -> GhosttyTerminalEngine? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttySurfaceCallbackContext>.fromOpaque(userdata)
            .takeUnretainedValue()
            .engine
    }

    static func runtime(fromUserdata userdata: UnsafeMutableRawPointer?) -> GhosttyTerminalRuntime? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttyRuntimeCallbackContext>.fromOpaque(userdata)
            .takeUnretainedValue()
            .runtime
    }

    static func runtime(fromApp app: ghostty_app_t?) -> GhosttyTerminalRuntime? {
        guard let app else { return nil }
        return runtime(fromUserdata: ghostty_app_userdata(app))
    }

    nonisolated
    static func performOnMainAsync(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    nonisolated
    static func performOnMainSync<T>(_ work: @escaping @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                work()
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    static func readClipboardString(for location: ghostty_clipboard_e) -> String {
        guard let pasteboard = pasteboard(for: location) else {
            return ""
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls.map(\.path).joined(separator: " ")
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return string
        }
        return saveClipboardImageIfNeeded(from: pasteboard) ?? ""
    }

    static func writeClipboardString(_ string: String, for location: ghostty_clipboard_e) {
        guard let pasteboard = pasteboard(for: location) else {
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    static func pasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
        switch location {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return NSPasteboard(name: NSPasteboard.Name("com.crispyvibe.app.selection"))
        default:
            return nil
        }
    }

    private static func saveClipboardImageIfNeeded(from pasteboard: NSPasteboard) -> String? {
        let types = pasteboard.types ?? []
        let hasText = types.contains(.string) || types.contains(.html) || types.contains(.rtf) || types.contains(.rtfd)
        guard !hasText else { return nil }

        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crispyvibes-terminal-paste", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "clipboard-\(timestamp)-\(UUID().uuidString.prefix(8)).png"
        let fileURL = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: fileURL, options: .atomic)
            return shellEscapeForClipboardPath(fileURL.path)
        } catch {
            return nil
        }
    }

    private static func shellEscapeForClipboardPath(_ value: String) -> String {
        ShellEscaping.singleQuote(value)
    }
}
