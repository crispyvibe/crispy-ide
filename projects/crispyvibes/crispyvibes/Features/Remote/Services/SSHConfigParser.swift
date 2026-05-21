// SSHConfigParser.swift — SSH Remote Development

import Foundation

/// Parses ~/.ssh/config into SSHConnectionProfile candidates.
enum SSHConfigParser {
    struct ParsedHost {
        let alias: String
        var hostname: String?
        var user: String?
        var port: UInt16?
        var identityFile: String?
    }

    static func parse(at path: String = "~/.ssh/config") -> [ParsedHost] {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else { return [] }
        return parse(content: content)
    }

    static func parse(content: String) -> [ParsedHost] {
        var hosts: [ParsedHost] = []
        var current: ParsedHost?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }

            if parts[0].lowercased() == "host" {
                if let finished = current, !finished.alias.contains("*") { hosts.append(finished) }
                current = ParsedHost(alias: parts[1])
            } else if var host = current {
                switch parts[0].lowercased() {
                case "hostname": host.hostname = parts[1]
                case "user": host.user = parts[1]
                case "port": host.port = UInt16(parts[1])
                case "identityfile": host.identityFile = NSString(string: parts[1]).expandingTildeInPath
                default: break
                }
                current = host
            }
        }
        if let finished = current, !finished.alias.contains("*") { hosts.append(finished) }
        return hosts
    }

    static func toProfile(_ parsed: ParsedHost) -> SSHConnectionProfile {
        SSHConnectionProfile(
            id: UUID(),
            displayName: parsed.alias,
            host: parsed.hostname ?? parsed.alias,
            port: parsed.port ?? 22,
            user: parsed.user ?? NSUserName(),
            authMethod: parsed.identityFile.map { .keyFile($0) } ?? .agent,
            importedFromConfig: true
        )
    }
}
