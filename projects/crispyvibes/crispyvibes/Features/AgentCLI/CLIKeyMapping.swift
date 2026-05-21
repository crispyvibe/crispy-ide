import Foundation

/// Maps human-readable key names to terminal escape sequences.
enum CLIKeyMapping {
    static func sequence(for key: String) -> String? {
        let normalized = key.trimmingCharacters(in: .whitespaces).lowercased()
        switch normalized {
        case "enter", "return": return "\r"
        case "tab": return "\t"
        case "escape", "esc": return "\u{1B}"
        case "backspace": return "\u{7F}"
        case "delete", "del": return "\u{1B}[3~"
        case "up": return "\u{1B}[A"
        case "down": return "\u{1B}[B"
        case "right": return "\u{1B}[C"
        case "left": return "\u{1B}[D"
        case "home": return "\u{1B}[H"
        case "end": return "\u{1B}[F"
        case "pageup": return "\u{1B}[5~"
        case "pagedown": return "\u{1B}[6~"
        default:
            if normalized.hasPrefix("ctrl+"), let last = normalized.dropFirst(5).first {
                if last.isLetter {
                    let upper = Character(last.uppercased())
                    if let ascii = upper.asciiValue, ascii >= 0x40, ascii <= 0x5F {
                        return String(UnicodeScalar(ascii - 0x40))
                    }
                }
                switch normalized.dropFirst(5) {
                case "[": return "\u{1B}"
                case "\\": return "\u{1C}"
                case "]": return "\u{1D}"
                case "^": return "\u{1E}"
                case "_": return "\u{1F}"
                default: return nil
                }
            }
            return nil
        }
    }
}
