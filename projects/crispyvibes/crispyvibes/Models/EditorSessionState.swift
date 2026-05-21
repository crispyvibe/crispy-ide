import Foundation

// MARK: - Editor Session State

/// Persisted state for the editor split layout and per-pane open files.
/// Stored per-vibespace alongside terminal session state.
struct EditorSessionState: Codable, Equatable {
    var splitTree: SplitNodeSnapshot
    var panes: [EditorPaneSnapshot]
    var activePaneID: UUID?
    var splitRatios: [String: Double] // UUID string → ratio
    var viewerScope: ViewerScope?

    static let empty = EditorSessionState(
        splitTree: .leaf(id: UUID()),
        panes: [],
        activePaneID: nil,
        splitRatios: [:]
    )
}

/// Serializable mirror of SplitPaneNode — stores structure only, no runtime content.
indirect enum SplitNodeSnapshot: Codable, Equatable {
    case leaf(id: UUID)
    case split(id: UUID, orientation: SplitOrientation, first: SplitNodeSnapshot, second: SplitNodeSnapshot, ratio: Double)

    var id: UUID {
        switch self {
        case .leaf(let id): return id
        case .split(let id, _, _, _, _): return id
        }
    }

    var allLeafIDs: [UUID] {
        switch self {
        case .leaf(let id): return [id]
        case .split(_, _, let first, let second, _):
            return first.allLeafIDs + second.allLeafIDs
        }
    }
}

/// Persisted state for a single editor pane's open files.
struct EditorPaneSnapshot: Codable, Equatable {
    var paneID: UUID
    var openFiles: [FileDocumentReference]
    var activeFile: FileDocumentReference?
    var terminalTabs: [TerminalTabReference]?
    var activeTerminalTabID: String?
    var browserTabs: [BrowserPaneTabSnapshot]?
    var activeBrowserTabID: String?
    var acpTabs: [ACPStandalonePaneSnapshot]?
    var activeTabID: String?

    init(
        paneID: UUID,
        openFiles: [FileDocumentReference],
        activeFile: FileDocumentReference? = nil,
        terminalTabs: [TerminalTabReference]? = nil,
        activeTerminalTabID: String? = nil,
        browserTabs: [BrowserPaneTabSnapshot]? = nil,
        activeBrowserTabID: String? = nil,
        acpTabs: [ACPStandalonePaneSnapshot]? = nil,
        activeTabID: String? = nil
    ) {
        self.paneID = paneID
        self.openFiles = openFiles
        self.activeFile = activeFile
        self.terminalTabs = terminalTabs
        self.activeTerminalTabID = activeTerminalTabID
        self.browserTabs = browserTabs
        self.activeBrowserTabID = activeBrowserTabID
        self.acpTabs = acpTabs
        self.activeTabID = activeTabID
    }

    init(
        paneID: UUID,
        openFilePaths: [String],
        activeFilePath: String? = nil,
        terminalTabs: [TerminalTabReference]? = nil,
        activeTerminalTabID: String? = nil,
        browserTabs: [BrowserPaneTabSnapshot]? = nil,
        activeBrowserTabID: String? = nil,
        acpTabs: [ACPStandalonePaneSnapshot]? = nil,
        activeTabID: String? = nil
    ) {
        self.init(
            paneID: paneID,
            openFiles: openFilePaths.map { FileDocumentReference(url: URL(fileURLWithPath: $0)) },
            activeFile: activeFilePath.map { FileDocumentReference(url: URL(fileURLWithPath: $0)) },
            terminalTabs: terminalTabs,
            activeTerminalTabID: activeTerminalTabID,
            browserTabs: browserTabs,
            activeBrowserTabID: activeBrowserTabID,
            acpTabs: acpTabs,
            activeTabID: activeTabID
        )
    }

    var openFilePaths: [String] {
        openFiles.map(\.filePath)
    }

    var activeFilePath: String? {
        activeFile?.filePath
    }

    private enum CodingKeys: String, CodingKey {
        case paneID
        case openFiles
        case activeFile
        case openFilePaths
        case activeFilePath
        case terminalTabs
        case activeTerminalTabID
        case browserTabs
        case activeBrowserTabID
        case acpTabs
        case activeTabID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paneID = try container.decode(UUID.self, forKey: .paneID)
        if let decodedOpenFiles = try container.decodeIfPresent([FileDocumentReference].self, forKey: .openFiles) {
            openFiles = decodedOpenFiles
        } else {
            let decodedPaths = try container.decodeIfPresent([String].self, forKey: .openFilePaths) ?? []
            openFiles = decodedPaths.map { FileDocumentReference(url: URL(fileURLWithPath: $0)) }
        }
        if let decodedActiveFile = try container.decodeIfPresent(FileDocumentReference.self, forKey: .activeFile) {
            activeFile = decodedActiveFile
        } else if let decodedActivePath = try container.decodeIfPresent(String.self, forKey: .activeFilePath) {
            activeFile = FileDocumentReference(url: URL(fileURLWithPath: decodedActivePath))
        } else {
            activeFile = nil
        }
        terminalTabs = try container.decodeIfPresent([TerminalTabReference].self, forKey: .terminalTabs)
        activeTerminalTabID = try container.decodeIfPresent(String.self, forKey: .activeTerminalTabID)
        browserTabs = try container.decodeIfPresent([BrowserPaneTabSnapshot].self, forKey: .browserTabs)
        activeBrowserTabID = try container.decodeIfPresent(String.self, forKey: .activeBrowserTabID)
        acpTabs = try container.decodeIfPresent([ACPStandalonePaneSnapshot].self, forKey: .acpTabs)
        activeTabID = try container.decodeIfPresent(String.self, forKey: .activeTabID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paneID, forKey: .paneID)
        try container.encode(openFiles, forKey: .openFiles)
        try container.encodeIfPresent(activeFile, forKey: .activeFile)
        try container.encode(openFilePaths, forKey: .openFilePaths)
        try container.encodeIfPresent(activeFilePath, forKey: .activeFilePath)
        try container.encodeIfPresent(terminalTabs, forKey: .terminalTabs)
        try container.encodeIfPresent(activeTerminalTabID, forKey: .activeTerminalTabID)
        try container.encodeIfPresent(browserTabs, forKey: .browserTabs)
        try container.encodeIfPresent(activeBrowserTabID, forKey: .activeBrowserTabID)
        try container.encodeIfPresent(acpTabs, forKey: .acpTabs)
        try container.encodeIfPresent(activeTabID, forKey: .activeTabID)
    }
}

struct TerminalTabReference: Codable, Equatable {
    var projectID: UUID
    var tabID: UUID
}

struct BrowserPaneTabSnapshot: Codable, Equatable {
    var reference: BrowserTabReference
    var sessionSnapshot: BrowserSessionSnapshot?
    var customTitle: String?
}
