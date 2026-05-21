import AppKit
import Foundation
import GhosttyKit

final class GhosttyRuntimeCallbackContext {
    weak var runtime: GhosttyTerminalRuntime?

    init(runtime: GhosttyTerminalRuntime) {
        self.runtime = runtime
    }
}

final class GhosttySurfaceCallbackContext {
    weak var engine: GhosttyTerminalEngine?

    init(engine: GhosttyTerminalEngine) {
        self.engine = engine
    }
}

func decodeUTF8(_ pointer: UnsafePointer<CChar>?, count: Int) -> String {
    guard let pointer, count > 0 else { return "" }
    let raw = UnsafeRawBufferPointer(start: pointer, count: count)
    return String(decoding: raw, as: UTF8.self)
}

struct UnsafeMutableRawPointerBox: @unchecked Sendable {
    let value: UnsafeMutableRawPointer?
}

struct UnsafePointerBox<Pointee>: @unchecked Sendable {
    let value: UnsafePointer<Pointee>?
}

extension NSScreen {
    var crispyvibesDisplayID: CGDirectDisplayID? {
        guard let value = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(value.uint32Value)
    }
}

private func blendedOpaqueColor(_ foreground: ProjectColorTag, over background: ProjectColorTag) -> ProjectColorTag {
    let alpha = foreground.alpha
    guard alpha < 0.999 else {
        return ProjectColorTag(red: foreground.red, green: foreground.green, blue: foreground.blue)
    }
    let inverseAlpha = 1 - alpha
    return ProjectColorTag(
        red: (foreground.red * alpha) + (background.red * inverseAlpha),
        green: (foreground.green * alpha) + (background.green * inverseAlpha),
        blue: (foreground.blue * alpha) + (background.blue * inverseAlpha)
    )
}

private func ghosttyColorToken(_ color: ProjectColorTag) -> String {
    let red = Int((color.red * 255).rounded())
    let green = Int((color.green * 255).rounded())
    let blue = Int((color.blue * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
}

let macOSReturnKeyCode: UInt32 = 36
let macOSEscapeKeyCode: UInt32 = 53
let macOSDeleteKeyCode: UInt32 = 51
let macOSForwardDeleteKeyCode: UInt32 = 117
let macOSTabKeyCode: UInt32 = 48
let macOSKeypadEnterKeyCode: UInt32 = 76
let macOSJKeyCode: UInt32 = 38
let macOSMKeyCode: UInt32 = 46
let macOSHomeKeyCode: UInt32 = 115
let macOSEndKeyCode: UInt32 = 119
let macOSPageUpKeyCode: UInt32 = 116
let macOSPageDownKeyCode: UInt32 = 121
let macOSLeftArrowKeyCode: UInt32 = 123
let macOSRightArrowKeyCode: UInt32 = 124
let macOSDownArrowKeyCode: UInt32 = 125
let macOSUpArrowKeyCode: UInt32 = 126
let queuedEnterMarker = Data([0x0D])

func shellEscapedCommand(_ executable: String, args: [String]) -> String {
    func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:")
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    return ([executable] + args).map(quote).joined(separator: " ")
}

enum GhosttyTerminalEngineSupport {
    private static let scrollbackBytesPerCell = 32
    private static let minimumScrollbackLimitBytes = 4 * 1024 * 1024
    private static let maximumScrollbackLimitBytes = 128 * 1024 * 1024

    static func startupBootstrapCommand() -> String {
        "printf '\\033[H\\033[2J\\033[3J' >/dev/tty"
    }

    static func initialSurfaceInput() -> String? {
        // Embedded Ghostty on macOS launches the shell through login(1), so
        // pre-seeding input here is too early to reliably clear the banner.
        nil
    }

    static func scrollbackLimitBytes(historySize: Int, columns: Int, rows: Int) -> Int {
        let totalLines = max(historySize, 0) + max(rows, 1)
        let cellsPerLine = max(columns, 1)
        let estimatedBytes = Int64(totalLines) * Int64(cellsPerLine) * Int64(scrollbackBytesPerCell)
        let clampedBytes = min(
            Int64(maximumScrollbackLimitBytes),
            max(Int64(minimumScrollbackLimitBytes), estimatedBytes)
        )
        return Int(clampedBytes)
    }

    static func runtimeConfigContents(
        for palette: AppThemePalette,
        historySize: Int,
        columns: Int,
        rows: Int
    ) -> String {
        let selectionBackground = blendedOpaqueColor(
            palette.terminalSelectionBackground,
            over: palette.canvasBackground
        )
        let scrollbackLimitBytes = scrollbackLimitBytes(
            historySize: historySize,
            columns: columns,
            rows: rows
        )
        return [
            "scrollback-limit = \(scrollbackLimitBytes)",
            "background = \(ghosttyColorToken(palette.canvasBackground))",
            "foreground = \(ghosttyColorToken(palette.terminalForeground))",
            "cursor-color = \(ghosttyColorToken(palette.terminalCaret))",
            "selection-background = \(ghosttyColorToken(selectionBackground))",
            "selection-foreground = cell-foreground"
        ].joined(separator: "\n") + "\n"
    }

    static func shouldSuppressInitialLoginBanner(in snapshot: String) -> Bool {
        let nonEmptyLines = snapshot
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let firstLine = nonEmptyLines.first else { return false }
        return firstLine.hasPrefix("Last login:")
    }

    static func likelyInteractivePrompt(in snapshot: String) -> Bool {
        let lines = snapshot
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let lastLine = lines.last else { return false }

        let barePromptPattern = #"^(?:[%#$>]|\u{276F}|\u{203A}|\u{00BB}|\u{27A4}|\u{279C}|\u{03BB}|❯|➜|➤|▶)\s*$"#
        if lastLine.range(of: barePromptPattern, options: .regularExpression) != nil {
            return true
        }

        let trailingPromptPattern = #".{0,120}(?:\s|^)(?:[%#$>]|❯|➜|➤|▶)\s*$"#
        return lastLine.range(of: trailingPromptPattern, options: .regularExpression) != nil
    }
}
