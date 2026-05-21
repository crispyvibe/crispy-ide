// PortForwardDetector.swift — SSH Remote Development

import Foundation

/// Detects port numbers from terminal output for auto-forwarding suggestions.
enum PortForwardDetector {
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            "(?:listening|running|started|serving).*?(?:on|at).*?(?:port\\s+|:)(\\d{2,5})",
            "localhost:(\\d{2,5})",
            "0\\.0\\.0\\.0:(\\d{2,5})",
            "127\\.0\\.0\\.1:(\\d{2,5})"
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    /// Scans terminal output text for port numbers. Returns unique detected ports.
    static func detectPorts(in text: String) -> [UInt16] {
        var ports = Set<UInt16>()
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            let matches = pattern.matches(in: text, range: range)
            for match in matches {
                guard match.numberOfRanges > 1,
                      let portRange = Range(match.range(at: 1), in: text),
                      let port = UInt16(text[portRange]),
                      (1024...65535).contains(port) else { continue }
                ports.insert(port)
            }
        }
        return ports.sorted()
    }
}
