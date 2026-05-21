import Foundation

/// Centralized shell escaping for paths and arguments sent to terminal sessions.
enum ShellEscaping {
    private static let safeCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:"
    )

    /// Single-quotes a value for safe use in shell contexts.
    /// Returns the value unquoted only if every character is in the safe allowlist.
    static func singleQuote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
