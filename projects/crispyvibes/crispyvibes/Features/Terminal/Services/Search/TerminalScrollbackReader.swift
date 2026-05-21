import AppKit
import Foundation
import GhosttyKit

/// Minimal POC: Reads the full scrollback buffer from a terminal session.
/// Supports both Ghostty (direct surface read) and tmux (capture-pane).
@MainActor
enum TerminalScrollbackReader {
    /// A single line match from a search.
    struct Match: Identifiable, Sendable {
        let id = UUID()
        let lineIndex: Int
        let lineText: String
    }

    /// Read full scrollback for a session. Prefers tmux capture if the session is tmux-backed,
    /// otherwise reads directly from the Ghostty surface.
    static func readScrollback(for session: TerminalSession) async -> String {
        // Tmux-backed sessions: use capture-pane for a snapshot of the full pane history.
        if let tmuxName = session.tmuxSessionName,
           TmuxService.isEnabled,
           let captured = await captureTmuxPane(sessionName: tmuxName) {
            return captured
        }

        // Ghostty engine: read full screen including scrollback.
        if let engine = session.engine as? GhosttyTerminalEngine {
            return readGhosttyScrollback(engine: engine)
        }

        return ""
    }

    /// Search the scrollback for occurrences of `query` (case-insensitive).
    /// Returns up to `limit` line matches, ordered top-to-bottom.
    static func search(
        in session: TerminalSession,
        query: String,
        limit: Int = 200
    ) async -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let content = await readScrollback(for: session)
        guard !content.isEmpty else { return [] }

        let needle = trimmed.lowercased()
        var results: [Match] = []
        for (index, line) in content.components(separatedBy: "\n").enumerated() {
            if line.lowercased().contains(needle) {
                results.append(Match(lineIndex: index, lineText: line))
                if results.count >= limit { break }
            }
        }
        return results
    }

    /// Scroll the terminal viewport to bring `match` into view.
    /// `allMatches` is the full result list — used to locate which Nth occurrence we want
    /// (only matters for tmux, which scrolls via repeated search-forward).
    static func scrollToMatch(
        in session: TerminalSession,
        match: Match,
        allMatches: [Match],
        query: String
    ) async {
        if let tmuxName = session.tmuxSessionName,
           TmuxService.isEnabled {
            let matchIndex = allMatches.firstIndex(where: { $0.id == match.id }) ?? 0
            await scrollTmuxToMatch(sessionName: tmuxName, query: query, matchIndex: matchIndex)
            return
        }

        if let engine = session.engine as? GhosttyTerminalEngine {
            scrollGhosttyToLine(engine: engine, lineIndex: match.lineIndex, totalLines: 0)
        }
    }

    /// Scroll to the most recent occurrence of `text` in the terminal.
    /// Used by up/down navigation through the centralized compose history store.
    static func scrollToText(in session: TerminalSession, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let tmuxName = session.tmuxSessionName,
           TmuxService.isEnabled {
            await scrollTmuxToTextBackward(sessionName: tmuxName, text: trimmed)
            return
        }

        if let engine = session.engine as? GhosttyTerminalEngine {
            scrollGhosttyToLastOccurrence(engine: engine, text: trimmed)
        }
    }

    /// Return the terminal viewport to live (bottom). For tmux, exits copy-mode.
    static func scrollToBottom(in session: TerminalSession) async {
        if let tmuxName = session.tmuxSessionName,
           TmuxService.isEnabled {
            await Task.detached(priority: .userInitiated) {
                guard let tmuxPath = TmuxService.tmuxPath else { return }
                runTmux(tmuxPath, args: ["send-keys", "-X", "-t", tmuxName, "cancel"])
            }.value
            return
        }

        if let engine = session.engine as? GhosttyTerminalEngine,
           let surface = engine.surface {
            performGhosttyAction(surface, "scroll_to_bottom")
        }
    }

    // MARK: - Ghostty

    private static func readGhosttyScrollback(engine: GhosttyTerminalEngine) -> String {
        guard let surface = engine.surface else { return "" }
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0
            ),
            rectangle: false
        )
        guard ghostty_surface_read_text(surface, selection, &text) else { return "" }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text, text.text_len > 0 else { return "" }
        let raw = UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len))
        return String(decoding: raw, as: UTF8.self)
    }

    private static func scrollGhosttyToLine(engine: GhosttyTerminalEngine, lineIndex: Int, totalLines: Int) {
        guard let surface = engine.surface else {
            print("[ScrollAssist] no surface")
            return
        }

        // Ghostty has a dedicated `scroll_to_row` action that takes an absolute
        // row index (0 = first row of full screen including scrollback).
        // Our `lineIndex` is exactly that — line index from the top of the buffer
        // when read with GHOSTTY_POINT_SCREEN.
        //
        // Center the match in the viewport by offsetting up by half a viewport.
        let viewportRows = engine.currentDimensions().rows
        let centeredRow = max(lineIndex - viewportRows / 2, 0)
        let action = "scroll_to_row:\(centeredRow)"
        print("[ScrollAssist] \(action) (lineIndex=\(lineIndex), totalLines=\(totalLines), viewportRows=\(viewportRows))")
        performGhosttyAction(surface, action)
    }

    private static func performGhosttyAction(_ surface: ghostty_surface_t, _ name: String) {
        name.withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(strlen(ptr)))
        }
    }

    private static func scrollGhosttyToLastOccurrence(engine: GhosttyTerminalEngine, text: String) {
        guard let surface = engine.surface else { return }

        let content = readGhosttyScrollback(engine: engine)
        guard !content.isEmpty else { return }

        let lines = content.components(separatedBy: "\n")
        var lastIndex: Int?
        for (index, line) in lines.enumerated() where line.contains(text) {
            lastIndex = index
        }
        guard let lineIndex = lastIndex else { return }

        let viewportRows = engine.currentDimensions().rows
        let centeredRow = max(lineIndex - viewportRows / 2, 0)
        performGhosttyAction(surface, "scroll_to_row:\(centeredRow)")
    }

    // MARK: - Tmux

    private static func captureTmuxPane(sessionName: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let tmuxPath = TmuxService.tmuxPath else { return nil }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = ["capture-pane", "-pS", "-", "-t", sessionName]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            } catch {
                return nil
            }
        }.value
    }

    private static func scrollTmuxToMatch(sessionName: String, query: String, matchIndex: Int) async {
        await Task.detached(priority: .userInitiated) {
            guard let tmuxPath = TmuxService.tmuxPath else { return }

            // Enter copy-mode in the pane.
            runTmux(tmuxPath, args: ["copy-mode", "-t", sessionName])

            // Jump to the top of the entire history so search-forward starts there.
            runTmux(tmuxPath, args: ["send-keys", "-X", "-t", sessionName, "history-top"])

            // Advance to the (matchIndex + 1)-th occurrence of the query by sending
            // search-forward repeatedly. tmux scrolls and highlights the match.
            for _ in 0...matchIndex {
                runTmux(tmuxPath, args: ["send-keys", "-X", "-t", sessionName, "search-forward", query])
            }
        }.value
    }

    private static func scrollTmuxToTextBackward(sessionName: String, text: String) async {
        await Task.detached(priority: .userInitiated) {
            guard let tmuxPath = TmuxService.tmuxPath else { return }
            runTmux(tmuxPath, args: ["copy-mode", "-t", sessionName])
            runTmux(tmuxPath, args: ["send-keys", "-X", "-t", sessionName, "history-bottom"])
            runTmux(tmuxPath, args: ["send-keys", "-X", "-t", sessionName, "search-backward", text])
        }.value
    }

    nonisolated private static func runTmux(_ executable: String, args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
