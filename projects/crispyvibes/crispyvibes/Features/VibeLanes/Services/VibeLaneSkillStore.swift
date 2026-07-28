import Combine
import Foundation

@MainActor
protocol AutomationSkillReferencePersisting: AnyObject {
    func loadSkillReferences() async throws -> [AutomationSkillReferenceRecord]
    func persistSkillReferences(_ records: [AutomationSkillReferenceRecord]) async throws
}

@MainActor
final class InMemoryAutomationSkillReferenceStore: AutomationSkillReferencePersisting {
    private var records: [AutomationSkillReferenceRecord]

    init(records: [AutomationSkillReferenceRecord] = []) {
        self.records = records
    }

    func loadSkillReferences() async throws -> [AutomationSkillReferenceRecord] {
        records
    }

    func persistSkillReferences(_ records: [AutomationSkillReferenceRecord]) async throws {
        self.records = records
    }
}

@MainActor
final class VibeLaneSkillStore: ObservableObject {
    @Published private(set) var skills: [VibeLaneSkillDefinition] = []
    @Published private(set) var persistenceError: String?

    private struct StoredMetadata: Codable {
        var category: String?
        var roles: [VibeLaneSkillRole]?
        var interaction: VibeLaneSkillInteraction?
        var requiredCommands: [String]?
    }

    enum StoreError: LocalizedError {
        case invalidName
        case duplicateName
        case missingSkillFile
        case invalidSkillFile
        case noSkillsFound
        case readOnly

        var errorDescription: String? {
            switch self {
            case .invalidName: AppStrings.Skills.invalidName
            case .duplicateName: AppStrings.Skills.duplicateName
            case .missingSkillFile: AppStrings.Skills.missingSkillFile
            case .invalidSkillFile: AppStrings.Skills.invalidSkillFile
            case .noSkillsFound: AppStrings.Skills.noSkillsFound
            case .readOnly: AppStrings.Skills.readOnly
            }
        }
    }

    nonisolated static let metadataFileName = "crispy.skill.json"

    let rootURL: URL
    private let bundledNames: Set<String>
    private let fileManager: FileManager
    private let referencePersistence: AutomationSkillReferencePersisting
    private var linkedReferences: Set<String> = []

    init(
        rootURL: URL,
        bundledNames: Set<String> = Set(VibeLaneSkillLibrary.starterNames),
        referencePersistence: AutomationSkillReferencePersisting? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.bundledNames = bundledNames
        self.referencePersistence = referencePersistence
            ?? InMemoryAutomationSkillReferenceStore()
        self.fileManager = fileManager
        reload()
    }

    func bootstrap() async {
        do {
            linkedReferences = Set(
                try await referencePersistence.loadSkillReferences().map(\.reference)
            )
            persistenceError = nil
            reload()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func reload() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var loaded = managedSkills()
        loaded.append(contentsOf: linkedSkills())
        skills = loaded.sorted {
            if $0.source != $1.source {
                return sourceOrder($0.source) < sourceOrder($1.source)
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    func create(name: String, detail: String, body: String) throws -> VibeLaneSkillDefinition {
        try create(
            VibeLaneSkillDraft(
                name: name,
                detail: detail,
                body: body,
                metadata: .default
            )
        )
    }

    @discardableResult
    func create(_ draft: VibeLaneSkillDraft) throws -> VibeLaneSkillDefinition {
        let name = draft.name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = Self.slug(for: trimmedName)
        guard !trimmedName.isEmpty, !slug.isEmpty else { throw StoreError.invalidName }

        let directory = rootURL.appendingPathComponent(slug, isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw StoreError.duplicateName
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("SKILL.md")
        do {
            try Self.render(name: trimmedName, detail: draft.detail, body: draft.body)
                .write(to: fileURL, atomically: true, encoding: .utf8)
            try saveMetadata(draft.metadata, in: directory)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        reload()
        return try skill(withReference: slug)
    }

    @discardableResult
    func update(
        _ skill: VibeLaneSkillDefinition,
        name: String,
        detail: String,
        body: String
    ) throws -> VibeLaneSkillDefinition {
        try update(
            skill,
            draft: VibeLaneSkillDraft(
                name: name,
                detail: detail,
                body: body,
                metadata: skill.metadata
            )
        )
    }

    @discardableResult
    func update(
        _ skill: VibeLaneSkillDefinition,
        draft: VibeLaneSkillDraft
    ) throws -> VibeLaneSkillDefinition {
        guard skill.isEditable else { throw StoreError.readOnly }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw StoreError.invalidName }
        try Self.render(name: trimmedName, detail: draft.detail, body: draft.body)
            .write(to: skill.fileURL, atomically: true, encoding: .utf8)
        try saveMetadata(draft.metadata, in: skill.rootURL)
        reload()
        return try self.skill(withReference: skill.reference)
    }

    @discardableResult
    func duplicate(_ skill: VibeLaneSkillDefinition) throws -> VibeLaneSkillDefinition {
        var candidate = "\(skill.name) Copy"
        var suffix = 2
        var destination = rootURL.appendingPathComponent(Self.slug(for: candidate), isDirectory: true)
        while fileManager.fileExists(atPath: destination.path) {
            candidate = "\(skill.name) Copy \(suffix)"
            suffix += 1
            destination = rootURL.appendingPathComponent(Self.slug(for: candidate), isDirectory: true)
        }

        try fileManager.copyItem(at: skill.rootURL, to: destination)
        let copiedSkillFile = destination.appendingPathComponent("SKILL.md")
        do {
            try Self.render(name: candidate, detail: skill.detail, body: skill.body)
                .write(to: copiedSkillFile, atomically: true, encoding: .utf8)
            try saveMetadata(skill.metadata, in: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        reload()
        return try self.skill(withReference: destination.lastPathComponent)
    }

    @discardableResult
    func link(_ selectedURL: URL) async throws -> VibeLaneSkillDefinition {
        guard let linked = try await linkCollection(selectedURL).first else {
            throw StoreError.noSkillsFound
        }
        return linked
    }

    @discardableResult
    func linkCollection(_ selectedURL: URL) async throws -> [VibeLaneSkillDefinition] {
        let files = try Self.discoverSkillFiles(at: selectedURL, fileManager: fileManager)
        guard !files.isEmpty else { throw StoreError.noSkillsFound }

        for fileURL in files {
            _ = try Self.parse(
                fileURL: fileURL,
                reference: fileURL.path,
                source: .linked,
                fileManager: fileManager
            )
        }
        var references = linkedReferences
        references.formUnion(files.map(\.path))
        try await persistLinkedReferences(references)
        linkedReferences = references
        reload()
        let imported = Set(files.map(\.path))
        return skills.filter { imported.contains($0.reference) }
    }

    func remove(_ skill: VibeLaneSkillDefinition) async throws {
        switch skill.source {
        case .bundled:
            throw StoreError.readOnly
        case .personal:
            try fileManager.removeItem(at: skill.fileURL.deletingLastPathComponent())
        case .linked:
            var references = linkedReferences
            references.remove(skill.fileURL.path)
            try await persistLinkedReferences(references)
            linkedReferences = references
        }
        reload()
    }

    func skill(withReference reference: String) throws -> VibeLaneSkillDefinition {
        guard let skill = skills.first(where: { $0.reference == reference }) else {
            throw StoreError.missingSkillFile
        }
        return skill
    }

    private func managedSkills() -> [VibeLaneSkillDefinition] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { directory in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            let source: VibeLaneSkillSource = bundledNames.contains(directory.lastPathComponent)
                ? .bundled
                : .personal
            return try? Self.parse(
                fileURL: directory.appendingPathComponent("SKILL.md"),
                reference: directory.lastPathComponent,
                source: source,
                fileManager: fileManager
            )
        }
    }

    private func linkedSkills() -> [VibeLaneSkillDefinition] {
        linkedReferences.compactMap { reference in
            let fileURL = URL(fileURLWithPath: reference)
            return try? Self.parse(
                fileURL: fileURL,
                reference: reference,
                source: .linked,
                fileManager: fileManager
            )
        }
    }

    private func persistLinkedReferences(_ references: Set<String>) async throws {
        do {
            try await referencePersistence.persistSkillReferences(
                references.sorted().map {
                    AutomationSkillReferenceRecord(reference: $0)
                }
            )
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            throw error
        }
    }

    private func sourceOrder(_ source: VibeLaneSkillSource) -> Int {
        switch source {
        case .bundled: 0
        case .personal: 1
        case .linked: 2
        }
    }

    nonisolated static func slug(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private nonisolated static func discoverSkillFiles(
        at selectedURL: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory) else {
            throw StoreError.missingSkillFile
        }

        if !isDirectory.boolValue {
            guard selectedURL.lastPathComponent == "SKILL.md" else {
                throw StoreError.missingSkillFile
            }
            return [selectedURL.standardizedFileURL]
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: selectedURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if Self.shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent == "SKILL.md" else { continue }
            files.append(url.standardizedFileURL)
            if files.count >= 200 { break }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private nonisolated static func parse(
        fileURL: URL,
        reference: String,
        source: VibeLaneSkillSource,
        fileManager: FileManager
    ) throws -> VibeLaneSkillDefinition {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw StoreError.missingSkillFile
        }
        let lines = content.components(separatedBy: .newlines)
        guard lines.first == "---",
              let end = lines.dropFirst().firstIndex(of: "---") else {
            throw StoreError.invalidSkillFile
        }
        let frontMatter = Array(lines[1..<end])
        guard let name = frontMatterValue("name", lines: frontMatter), !name.isEmpty else {
            throw StoreError.invalidSkillFile
        }
        let bodyStart = lines.index(after: end)
        let body = lines[bodyStart...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURL = fileURL.deletingLastPathComponent()
        let storedMetadata = loadMetadata(from: rootURL, fileManager: fileManager)
        let inferredInteraction: VibeLaneSkillInteraction = content.contains("AskUserQuestion")
            || content.localizedCaseInsensitiveContains("ask the user")
            || content.localizedCaseInsensitiveContains("stop and wait")
            ? .interactive
            : .unattended
        let category = storedMetadata?.category
            ?? inferredCategory(rootURL: rootURL, source: source)
        let roles = normalizedRoles(storedMetadata?.roles ?? VibeLaneSkillRole.allCases)
        let metadata = VibeLaneSkillMetadata(
            category: category,
            roles: roles,
            interaction: storedMetadata?.interaction ?? inferredInteraction,
            requiredCommands: normalizedCommands(storedMetadata?.requiredCommands ?? [])
        )
        let scanned = scanResources(rootURL: rootURL, fileManager: fileManager)
        var issues = scanned.issues
        if body.isEmpty {
            issues.append(.emptyInstructions)
        }
        for command in metadata.requiredCommands where !commandExists(command) {
            issues.append(.missingCommand(command))
        }
        for path in localMarkdownReferences(in: body) {
            let resourceURL = rootURL.appendingPathComponent(path).standardizedFileURL
            guard resourceURL.path.hasPrefix(rootURL.standardizedFileURL.path),
                  fileManager.fileExists(atPath: resourceURL.path) else {
                issues.append(.missingReference(path))
                continue
            }
        }
        return VibeLaneSkillDefinition(
            reference: reference,
            name: name,
            detail: frontMatterValue("description", lines: frontMatter) ?? "",
            body: body,
            source: source,
            rootURL: rootURL,
            fileURL: fileURL,
            metadata: metadata,
            resources: scanned.resources,
            issues: Array(Set(issues))
        )
    }

    private nonisolated static func render(name: String, detail: String, body: String) -> String {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedDetail = detail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "\\\"")
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        ---
        name: "\(escapedName)"
        description: "\(escapedDetail)"
        ---

        \(trimmedBody)
        """
    }

    private func saveMetadata(_ metadata: VibeLaneSkillMetadata, in directory: URL) throws {
        let stored = StoredMetadata(
            category: metadata.category,
            roles: metadata.roles,
            interaction: metadata.interaction,
            requiredCommands: metadata.requiredCommands
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stored)
        try data.write(
            to: directory.appendingPathComponent(Self.metadataFileName),
            options: [.atomic]
        )
    }

    private nonisolated static func loadMetadata(
        from directory: URL,
        fileManager: FileManager
    ) -> StoredMetadata? {
        let url = directory.appendingPathComponent(metadataFileName)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredMetadata.self, from: data)
    }

    private nonisolated static func frontMatterValue(
        _ key: String,
        lines: [String]
    ) -> String? {
        guard let index = lines.firstIndex(where: { line in
            guard let separator = line.firstIndex(of: ":") else { return false }
            return line[..<separator].trimmingCharacters(in: .whitespaces) == key
        }), let separator = lines[index].firstIndex(of: ":") else {
            return nil
        }

        let raw = String(lines[index][lines[index].index(after: separator)...])
            .trimmingCharacters(in: .whitespaces)
        if raw == "|" || raw == ">" {
            var values: [String] = []
            for line in lines.dropFirst(index + 1) {
                if !line.hasPrefix(" "), !line.hasPrefix("\t") { break }
                values.append(line.trimmingCharacters(in: .whitespaces))
            }
            let separator = raw == ">" ? " " : "\n"
            return values.joined(separator: separator)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return unquote(raw)
    }

    private nonisolated static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private nonisolated static func inferredCategory(
        rootURL: URL,
        source: VibeLaneSkillSource
    ) -> String {
        guard source == .linked else { return "General" }
        let parent = rootURL.deletingLastPathComponent().lastPathComponent
        let excluded = ["skills", "skill", "agents", ".claude", ".codex"]
        guard !parent.isEmpty, !excluded.contains(parent.lowercased()) else {
            return "Imported"
        }
        return parent
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private nonisolated static func normalizedRoles(
        _ roles: [VibeLaneSkillRole]
    ) -> [VibeLaneSkillRole] {
        let values = Set(roles)
        let ordered = VibeLaneSkillRole.allCases.filter(values.contains)
        return ordered.isEmpty ? VibeLaneSkillRole.allCases : ordered
    }

    private nonisolated static func normalizedCommands(_ commands: [String]) -> [String] {
        Array(Set(commands.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }

    private nonisolated static func scanResources(
        rootURL: URL,
        fileManager: FileManager
    ) -> (resources: [VibeLaneSkillResource], issues: [VibeLaneSkillIssue]) {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return ([], [])
        }

        var resources: [VibeLaneSkillResource] = []
        var didReachLimit = false
        while let url = enumerator.nextObject() as? URL {
            if shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent != "SKILL.md",
                  url.lastPathComponent != metadataFileName,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let relativePath = String(
                url.standardizedFileURL.path.dropFirst(rootURL.standardizedFileURL.path.count + 1)
            )
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            resources.append(
                VibeLaneSkillResource(
                    relativePath: relativePath,
                    kind: resourceKind(for: relativePath),
                    fileURL: url,
                    byteCount: values?.fileSize ?? 0
                )
            )
            if resources.count >= 500 {
                didReachLimit = true
                break
            }
        }
        let sorted = resources.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return (sorted, didReachLimit ? [.resourceScanLimit(500)] : [])
    }

    private nonisolated static func shouldSkipDirectory(_ url: URL) -> Bool {
        let skipped = Set([
            ".git", ".build", "DerivedData", "node_modules", "Pods",
            ".swiftpm", "__pycache__"
        ])
        return skipped.contains(url.lastPathComponent)
    }

    private nonisolated static func resourceKind(
        for relativePath: String
    ) -> VibeLaneSkillResourceKind {
        let first = relativePath.split(separator: "/").first?.lowercased()
        switch first {
        case "references", "reference", "docs": return .reference
        case "scripts", "bin": return .script
        case "assets", "templates": return .asset
        case "agents": return .agentMetadata
        default: return .other
        }
    }

    private nonisolated static func localMarkdownReferences(in body: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"\[[^\]]+\]\(([^)]+)\)"#
        ) else {
            return []
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return expression.matches(in: body, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: body) else { return nil }
            var value = String(body[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("<"), value.hasSuffix(">") {
                value = String(value.dropFirst().dropLast())
            }
            value = value.components(separatedBy: "#").first ?? value
            guard !value.isEmpty,
                  !value.hasPrefix("#"),
                  !value.hasPrefix("/"),
                  !value.hasPrefix("~"),
                  !value.contains("://"),
                  !value.hasPrefix("mailto:") else {
                return nil
            }
            return value.removingPercentEncoding ?? value
        }
    }

    private nonisolated static func commandExists(_ command: String) -> Bool {
        let fileManager = FileManager.default
        if command.contains("/") {
            return fileManager.isExecutableFile(atPath: NSString(string: command).expandingTildeInPath)
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { directory in
            fileManager.isExecutableFile(
                atPath: URL(fileURLWithPath: String(directory))
                    .appendingPathComponent(command)
                    .path
            )
        }
    }
}
