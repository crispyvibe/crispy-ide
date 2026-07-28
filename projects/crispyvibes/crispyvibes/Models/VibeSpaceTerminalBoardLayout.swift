import Foundation

enum VibeSpaceTerminalBoardDropIntent: Equatable {
    case insertLeft(of: UUID)
    case insertRight(of: UUID)
    case insertAbove(of: UUID)
    case insertBelow(of: UUID)
    case swap(with: UUID)
}

enum TileContentKind: Equatable {
    case terminal
    case file(URL)
    case vibeCast
    case vibeLanes
    case browser(URL)
    case acp(ACPStandalonePaneSnapshot)
}

struct VibeSpaceTerminalBoardTile: Identifiable, Equatable {
    let id: UUID
    var heightWeight: Double
    var projectPath: String?
    var terminalTabID: UUID?
    var workingDirectoryPath: String
    var contentKind: TileContentKind
    var browserSession: BrowserSessionSnapshot?

    init(
        id: UUID = UUID(),
        heightWeight: Double = 1,
        projectPath: String? = nil,
        terminalTabID: UUID? = nil,
        workingDirectoryPath: String,
        contentKind: TileContentKind = .terminal,
        browserSession: BrowserSessionSnapshot? = nil
    ) {
        self.id = id
        self.heightWeight = heightWeight
        self.projectPath = projectPath
        self.terminalTabID = terminalTabID
        self.workingDirectoryPath = workingDirectoryPath
        self.contentKind = contentKind
        self.browserSession = browserSession
    }

    var workingDirectoryURL: URL {
        URL(fileURLWithPath: workingDirectoryPath).standardizedFileURL
    }

    func normalized() -> VibeSpaceTerminalBoardTile {
        let normalizedPath = workingDirectoryURL.path
        return VibeSpaceTerminalBoardTile(
            id: id,
            heightWeight: VibeSpaceTerminalBoardColumn.normalizedWeight(heightWeight),
            projectPath: projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            terminalTabID: terminalTabID,
            workingDirectoryPath: normalizedPath,
            contentKind: contentKind,
            browserSession: browserSession
        )
    }

    var isVibeCast: Bool { contentKind == .vibeCast }
    var isVibeLanes: Bool { contentKind == .vibeLanes }
    var isFile: Bool { if case .file = contentKind { return true }; return false }
    var isTerminal: Bool { contentKind == .terminal }

    var fileURL: URL? {
        if case .file(let url) = contentKind { return url }
        return nil
    }

    var isBrowser: Bool { if case .browser = contentKind { return true }; return false }
    var browserURL: URL? { if case .browser(let url) = contentKind { return url }; return nil }
    var isACP: Bool { if case .acp = contentKind { return true }; return false }
    var acpSnapshot: ACPStandalonePaneSnapshot? {
        if case .acp(let snapshot) = contentKind { return snapshot }
        return nil
    }
}

// MARK: - TileContentKind Codable

extension TileContentKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, filePath, urlString, acpSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "file":
            let path = try container.decode(String.self, forKey: .filePath)
            self = .file(URL(fileURLWithPath: path))
        case "vibeCast":
            self = .vibeCast
        case "vibeLanes":
            self = .vibeLanes
        case "browser":
            // Decode from urlString, fall back to filePath for backward compat
            let raw = try container.decodeIfPresent(String.self, forKey: .urlString)
                ?? container.decodeIfPresent(String.self, forKey: .filePath)
                ?? "about:blank"
            self = .browser(URL(string: raw) ?? URL(string: "about:blank")!)
        case "acp":
            self = .acp(try container.decode(ACPStandalonePaneSnapshot.self, forKey: .acpSnapshot))
        default:
            self = .terminal
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal:
            try container.encode("terminal", forKey: .type)
        case .file(let url):
            try container.encode("file", forKey: .type)
            try container.encode(url.standardizedFileURL.path, forKey: .filePath)
        case .vibeCast:
            try container.encode("vibeCast", forKey: .type)
        case .vibeLanes:
            try container.encode("vibeLanes", forKey: .type)
        case .browser(let url):
            try container.encode("browser", forKey: .type)
            try container.encode(url.absoluteString, forKey: .urlString)
        case .acp(let snapshot):
            try container.encode("acp", forKey: .type)
            try container.encode(snapshot, forKey: .acpSnapshot)
        }
    }
}

// MARK: - VibeSpaceTerminalBoardTile Codable

extension VibeSpaceTerminalBoardTile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, heightWeight, projectPath, terminalTabID
        case workingDirectoryPath, contentKind, isVibeCast, browserSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        heightWeight = try container.decodeIfPresent(Double.self, forKey: .heightWeight) ?? 1
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        terminalTabID = try container.decodeIfPresent(UUID.self, forKey: .terminalTabID)
        workingDirectoryPath = try container.decodeIfPresent(String.self, forKey: .workingDirectoryPath) ?? ""
        browserSession = try container.decodeIfPresent(BrowserSessionSnapshot.self, forKey: .browserSession)
        if let kind = try container.decodeIfPresent(TileContentKind.self, forKey: .contentKind) {
            contentKind = kind
        } else if let legacy = try container.decodeIfPresent(Bool.self, forKey: .isVibeCast), legacy {
            contentKind = .vibeCast
        } else {
            contentKind = .terminal
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(heightWeight, forKey: .heightWeight)
        try container.encodeIfPresent(projectPath, forKey: .projectPath)
        try container.encodeIfPresent(terminalTabID, forKey: .terminalTabID)
        try container.encode(workingDirectoryPath, forKey: .workingDirectoryPath)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encodeIfPresent(browserSession, forKey: .browserSession)
    }
}

struct VibeSpaceTerminalBoardColumn: Identifiable, Codable, Equatable {
    let id: UUID
    var widthWeight: Double
    var tiles: [VibeSpaceTerminalBoardTile]

    init(
        id: UUID = UUID(),
        widthWeight: Double = 1,
        tiles: [VibeSpaceTerminalBoardTile]
    ) {
        self.id = id
        self.widthWeight = widthWeight
        self.tiles = tiles
    }

    static func normalizedWeight(_ value: Double) -> Double {
        let sanitized = value.isFinite ? value : 1
        return max(sanitized, 0.01)
    }

    func normalized(maxRows: Int) -> VibeSpaceTerminalBoardColumn {
        let normalizedTiles = tiles
            .prefix(maxRows)
            .map { $0.normalized() }

        return VibeSpaceTerminalBoardColumn(
            id: id,
            widthWeight: Self.normalizedWeight(widthWeight),
            tiles: Self.normalizedTilesByWeight(Array(normalizedTiles))
        )
    }

    static func normalizedTilesByWeight(_ tiles: [VibeSpaceTerminalBoardTile]) -> [VibeSpaceTerminalBoardTile] {
        guard !tiles.isEmpty else { return [] }
        let totalWeight = tiles.reduce(0.0) { $0 + normalizedWeight($1.heightWeight) }
        guard totalWeight > 0 else {
            return tiles.map { tile in
                var updated = tile
                updated.heightWeight = 1 / Double(tiles.count)
                return updated
            }
        }

        return tiles.map { tile in
            var updated = tile
            updated.heightWeight = normalizedWeight(tile.heightWeight) / totalWeight
            return updated
        }
    }
}

struct VibeSpaceTerminalBoardLayout: Codable, Equatable {
    static let maxColumns = 4
    static let maxRowsPerColumn = 4
    static let maximumTileCount = maxColumns * maxRowsPerColumn
    static let empty = VibeSpaceTerminalBoardLayout(columns: [], activeTileID: nil)

    var columns: [VibeSpaceTerminalBoardColumn]
    var activeTileID: UUID?
    var minimizedTiles: [VibeSpaceTerminalBoardTile] = []

    var tiles: [VibeSpaceTerminalBoardTile] {
        columns.flatMap(\.tiles)
    }

    var tileCount: Int {
        tiles.count
    }

    var tileIDs: [UUID] {
        tiles.map(\.id)
    }

    var allTileIDs: [UUID] {
        tiles.map(\.id) + minimizedTiles.map(\.id)
    }

    func tile(for tileID: UUID) -> VibeSpaceTerminalBoardTile? {
        guard let position = position(of: tileID) else { return nil }
        return columns[position.columnIndex].tiles[position.rowIndex]
    }

    func position(of tileID: UUID) -> (columnIndex: Int, rowIndex: Int)? {
        for columnIndex in columns.indices {
            if let rowIndex = columns[columnIndex].tiles.firstIndex(where: { $0.id == tileID }) {
                return (columnIndex, rowIndex)
            }
        }
        return nil
    }

    mutating func updateTile(_ tileID: UUID, mutate: (inout VibeSpaceTerminalBoardTile) -> Void) {
        guard let position = position(of: tileID) else { return }
        mutate(&columns[position.columnIndex].tiles[position.rowIndex])
    }

    mutating func removeTile(withID tileID: UUID) -> VibeSpaceTerminalBoardTile? {
        if let minimizedIndex = minimizedTiles.firstIndex(where: { $0.id == tileID }) {
            return minimizedTiles.remove(at: minimizedIndex)
        }

        guard let position = position(of: tileID) else { return nil }
        let removedTile = columns[position.columnIndex].tiles.remove(at: position.rowIndex)
        if columns[position.columnIndex].tiles.isEmpty {
            columns.remove(at: position.columnIndex)
        }

        if activeTileID == tileID {
            activeTileID = columns.first?.tiles.first?.id
        }

        return removedTile
    }

    mutating func minimizeTile(withID tileID: UUID) -> Bool {
        guard let position = position(of: tileID) else { return false }
        let tile = columns[position.columnIndex].tiles.remove(at: position.rowIndex)
        if columns[position.columnIndex].tiles.isEmpty {
            columns.remove(at: position.columnIndex)
        }
        minimizedTiles.append(tile)

        if activeTileID == tileID {
            activeTileID = columns.first?.tiles.first?.id
        }

        return true
    }

    mutating func restoreTile(withID tileID: UUID) -> Bool {
        guard let index = minimizedTiles.firstIndex(where: { $0.id == tileID }) else { return false }
        guard tileCount < Self.maximumTileCount else { return false }
        let tile = minimizedTiles.remove(at: index)
        return insertNewTile(tile, activeHintTileID: activeTileID, activateInsertedTile: true)
    }

    func normalized() -> VibeSpaceTerminalBoardLayout {
        var seenTileIDs = Set<UUID>()
        var normalizedColumns: [VibeSpaceTerminalBoardColumn] = []
        normalizedColumns.reserveCapacity(min(columns.count, Self.maxColumns))

        var tileBudget = Self.maximumTileCount
        for column in columns.prefix(Self.maxColumns) {
            guard tileBudget > 0 else { break }

            var dedupedTiles: [VibeSpaceTerminalBoardTile] = []
            dedupedTiles.reserveCapacity(min(column.tiles.count, Self.maxRowsPerColumn))

            for tile in column.tiles {
                guard tileBudget > 0 else { break }
                guard seenTileIDs.insert(tile.id).inserted else { continue }
                dedupedTiles.append(tile.normalized())
                tileBudget -= 1
                if dedupedTiles.count >= Self.maxRowsPerColumn {
                    break
                }
            }

            guard !dedupedTiles.isEmpty else { continue }
            var normalizedColumn = VibeSpaceTerminalBoardColumn(
                id: column.id,
                widthWeight: VibeSpaceTerminalBoardColumn.normalizedWeight(column.widthWeight),
                tiles: dedupedTiles
            )
            normalizedColumn.tiles = VibeSpaceTerminalBoardColumn.normalizedTilesByWeight(normalizedColumn.tiles)
            normalizedColumns.append(normalizedColumn)
        }

        let normalizedColumnsByWeight = Self.normalizedColumnsByWeight(normalizedColumns)
        let normalizedActiveTileID = activeTileID.flatMap { candidateID in
            normalizedColumnsByWeight.contains(where: { column in
                column.tiles.contains(where: { $0.id == candidateID })
            }) ? candidateID : nil
        } ?? normalizedColumnsByWeight.first?.tiles.first?.id

        let normalizedMinimized = minimizedTiles.filter { seenTileIDs.insert($0.id).inserted }.map { $0.normalized() }

        var result = VibeSpaceTerminalBoardLayout(
            columns: normalizedColumnsByWeight,
            activeTileID: normalizedActiveTileID
        )
        result.minimizedTiles = normalizedMinimized
        return result
    }

    private static func normalizedColumnsByWeight(_ columns: [VibeSpaceTerminalBoardColumn]) -> [VibeSpaceTerminalBoardColumn] {
        guard !columns.isEmpty else { return [] }

        let totalWeight = columns.reduce(0.0) { partialResult, column in
            partialResult + VibeSpaceTerminalBoardColumn.normalizedWeight(column.widthWeight)
        }

        guard totalWeight > 0 else {
            return columns.map { column in
                var updated = column
                updated.widthWeight = 1 / Double(columns.count)
                return updated
            }
        }

        return columns.map { column in
            var updated = column
            updated.widthWeight = VibeSpaceTerminalBoardColumn.normalizedWeight(column.widthWeight) / totalWeight
            return updated
        }
    }
}

enum VibeSpaceTerminalBoardSurfaceKind: String, Codable, Equatable {
    case primary
    case detached
}

struct VibeSpaceTerminalBoardWindowPlacement: Codable, Equatable {
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
    var screenID: String?

    init(
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        screenID: String? = nil
    ) {
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.screenID = screenID
    }
}

struct VibeSpaceTerminalBoardSurface: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: VibeSpaceTerminalBoardSurfaceKind
    var layout: VibeSpaceTerminalBoardLayout
    var title: String
    var placement: VibeSpaceTerminalBoardWindowPlacement?
    var isOpen: Bool

    init(
        id: UUID = UUID(),
        kind: VibeSpaceTerminalBoardSurfaceKind,
        layout: VibeSpaceTerminalBoardLayout,
        title: String = "",
        placement: VibeSpaceTerminalBoardWindowPlacement? = nil,
        isOpen: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.layout = layout
        self.title = title
        self.placement = placement
        self.isOpen = isOpen
    }

    func normalized() -> VibeSpaceTerminalBoardSurface {
        VibeSpaceTerminalBoardSurface(
            id: id,
            kind: kind,
            layout: layout.normalized(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            placement: placement,
            isOpen: isOpen
        )
    }
}

struct VibeSpaceTerminalBoardState: Codable, Equatable {
    static let primarySurfaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var primarySurfaceID: UUID
    var surfaces: [VibeSpaceTerminalBoardSurface]

    init(
        primarySurfaceID: UUID = Self.primarySurfaceID,
        surfaces: [VibeSpaceTerminalBoardSurface] = []
    ) {
        self.primarySurfaceID = primarySurfaceID
        self.surfaces = surfaces
    }

    static let empty = VibeSpaceTerminalBoardState(
        surfaces: [
            VibeSpaceTerminalBoardSurface(
                id: VibeSpaceTerminalBoardState.primarySurfaceID,
                kind: .primary,
                layout: .empty,
                title: "Primary",
                isOpen: true
            )
        ]
    )

    static func fromLegacyLayout(_ layout: VibeSpaceTerminalBoardLayout) -> VibeSpaceTerminalBoardState {
        VibeSpaceTerminalBoardState(
            surfaces: [
                VibeSpaceTerminalBoardSurface(
                    id: primarySurfaceID,
                    kind: .primary,
                    layout: layout,
                    title: "Primary",
                    isOpen: true
                )
            ]
        ).normalized()
    }

    var primaryLayout: VibeSpaceTerminalBoardLayout {
        surface(id: primarySurfaceID)?.layout ?? .empty
    }

    var allTileIDs: [UUID] {
        surfaces.flatMap { $0.layout.allTileIDs }
    }

    func surface(id: UUID) -> VibeSpaceTerminalBoardSurface? {
        surfaces.first(where: { $0.id == id })
    }

    func layout(for surfaceID: UUID) -> VibeSpaceTerminalBoardLayout {
        surface(id: surfaceID)?.layout ?? .empty
    }

    func normalized() -> VibeSpaceTerminalBoardState {
        var seenSurfaceIDs = Set<UUID>()
        var seenTileIDs = Set<UUID>()
        var normalizedSurfaces: [VibeSpaceTerminalBoardSurface] = []
        normalizedSurfaces.reserveCapacity(max(surfaces.count, 1))

        for surface in surfaces {
            guard seenSurfaceIDs.insert(surface.id).inserted else { continue }
            var normalizedSurface = surface.normalized()
            normalizedSurface.layout = normalizedSurface.layout.removingDuplicateTiles(seenTileIDs: &seenTileIDs)
            if normalizedSurface.kind == .primary {
                normalizedSurface.isOpen = true
            }
            if normalizedSurface.kind == .detached,
               normalizedSurface.layout.tiles.isEmpty,
               normalizedSurface.layout.minimizedTiles.isEmpty {
                continue
            }
            normalizedSurfaces.append(normalizedSurface)
        }

        if !normalizedSurfaces.contains(where: { $0.id == primarySurfaceID }) {
            normalizedSurfaces.insert(
                VibeSpaceTerminalBoardSurface(
                    id: primarySurfaceID,
                    kind: .primary,
                    layout: .empty,
                    title: "Primary",
                    isOpen: true
                ),
                at: 0
            )
        }

        return VibeSpaceTerminalBoardState(
            primarySurfaceID: primarySurfaceID,
            surfaces: normalizedSurfaces
        )
    }
}

private extension VibeSpaceTerminalBoardLayout {
    func removingDuplicateTiles(seenTileIDs: inout Set<UUID>) -> VibeSpaceTerminalBoardLayout {
        var copy = self
        for tile in tiles where !seenTileIDs.insert(tile.id).inserted {
            _ = copy.removeTile(withID: tile.id)
        }
        copy.minimizedTiles.removeAll { tile in
            !seenTileIDs.insert(tile.id).inserted
        }
        return copy.normalized()
    }
}

extension VibeSpaceTerminalBoardLayout {
    private enum CodingKeys: String, CodingKey {
        case columns
        case activeTileID
        case tiles
        case minimizedTiles
    }

    private struct LegacyTile: Decodable {
        let id: UUID
        let column: Int
        let row: Int
        let projectPath: String?
        let terminalTabID: UUID?
        let workingDirectoryPath: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeTileID = try container.decodeIfPresent(UUID.self, forKey: .activeTileID)
        minimizedTiles = try container.decodeIfPresent([VibeSpaceTerminalBoardTile].self, forKey: .minimizedTiles) ?? []

        if let decodedColumns = try container.decodeIfPresent([VibeSpaceTerminalBoardColumn].self, forKey: .columns) {
            columns = decodedColumns
            self = normalized()
            return
        }

        let legacyTiles = try container.decodeIfPresent([LegacyTile].self, forKey: .tiles) ?? []
        columns = Self.columnsFromLegacyTiles(legacyTiles)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns, forKey: .columns)
        try container.encodeIfPresent(activeTileID, forKey: .activeTileID)
        if !minimizedTiles.isEmpty {
            try container.encode(minimizedTiles, forKey: .minimizedTiles)
        }
    }

    private static func columnsFromLegacyTiles(_ legacyTiles: [LegacyTile]) -> [VibeSpaceTerminalBoardColumn] {
        guard !legacyTiles.isEmpty else { return [] }

        let sorted = legacyTiles.sorted { lhs, rhs in
            if lhs.column != rhs.column {
                return lhs.column < rhs.column
            }
            if lhs.row != rhs.row {
                return lhs.row < rhs.row
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var groupedByColumn: [Int: [VibeSpaceTerminalBoardTile]] = [:]
        for legacy in sorted {
            let tile = VibeSpaceTerminalBoardTile(
                id: legacy.id,
                heightWeight: 1,
                projectPath: legacy.projectPath,
                terminalTabID: legacy.terminalTabID,
                workingDirectoryPath: legacy.workingDirectoryPath
            )
            groupedByColumn[legacy.column, default: []].append(tile)
        }

        return groupedByColumn
            .keys
            .sorted()
            .map { columnIndex in
                VibeSpaceTerminalBoardColumn(
                    widthWeight: 1,
                    tiles: groupedByColumn[columnIndex] ?? []
                )
            }
    }
}
