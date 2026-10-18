import Combine
import Foundation
import SwiftUI

/// Canonical live-owner lookup used to build safe Spotlight navigation metadata.
@MainActor
struct SpotlightMetadataResolver {
    let projectColorTag: (AnyProjectSession) -> ProjectColorTag?
    let fileGroup: (UUID) -> EditorGroupStore?
    let browserViewModel: (UUID) -> BrowserPanelViewModel?

    init(
        projectColorTag: @escaping (AnyProjectSession) -> ProjectColorTag?,
        fileGroup: @escaping (UUID) -> EditorGroupStore? = { _ in nil },
        browserViewModel: @escaping (UUID) -> BrowserPanelViewModel? = { _ in nil }
    ) {
        self.projectColorTag = projectColorTag
        self.fileGroup = fileGroup
        self.browserViewModel = browserViewModel
    }
}

/// Non-content metadata rendered by Spotlight shelf and overview cards.
@MainActor
struct SpotlightItemMetadata {
    let item: SpotlightItem
    let title: String
    let secondary: String
    let group: String
    let iconName: String
    let accentColor: Color?
    var statusLines: [String] = []
    var activityState: TerminalTabActivityState?

    var id: SpotlightPersistentItemID { item.persistentID }
    var safeAccessibilityID: String { item.persistentID.safeToken }

    static func make(item: SpotlightItem, resolver: SpotlightMetadataResolver) -> SpotlightItemMetadata {
        switch item {
        case let .terminal(project, tab):
            let activity = project.terminalViewModel.tabActivityStateOrInactive(for: tab.id)
            return SpotlightItemMetadata(
                item: item,
                title: tab.title.isEmpty ? AppStrings.Spotlight.terminal : tab.title,
                secondary: project.title,
                group: project.title,
                iconName: "terminal",
                accentColor: resolver.projectColorTag(project)?.color,
                statusLines: terminalStatusLines(directoryURL: tab.workingDirectory, activity: activity),
                activityState: activity
            )
        case let .standaloneTerminal(_, _, terminalViewModel, tab):
            let activity = terminalViewModel.tabActivityStateOrInactive(for: tab.id)
            return SpotlightItemMetadata(
                item: item,
                title: tab.title.isEmpty ? AppStrings.Spotlight.terminal : tab.title,
                secondary: AppStrings.Spotlight.standalone,
                group: AppStrings.Spotlight.standalone,
                iconName: "terminal",
                accentColor: nil,
                statusLines: terminalStatusLines(directoryURL: tab.workingDirectory, activity: activity),
                activityState: activity
            )
        case .vibeCast:
            return SpotlightItemMetadata(
                item: item,
                title: AppStrings.VibeCast.title,
                secondary: AppStrings.Spotlight.vibeSpace,
                group: AppStrings.Spotlight.vibeSpace,
                iconName: "antenna.radiowaves.left.and.right",
                accentColor: nil
            )
        case .vibeLanes:
            return SpotlightItemMetadata(
                item: item,
                title: AppStrings.VibeLanes.title,
                secondary: AppStrings.Spotlight.vibeSpace,
                group: AppStrings.Spotlight.vibeSpace,
                iconName: VibeLaneVisualIdentity.symbolName,
                accentColor: nil
            )
        case let .acp(_, _, title, accentColor):
            return SpotlightItemMetadata(
                item: item,
                title: title,
                secondary: AppStrings.Spotlight.agent,
                group: AppStrings.Spotlight.agents,
                iconName: "sparkles",
                accentColor: accentColor
            )
        case let .file(tileID, fallbackURL):
            let currentURL = resolver.fileGroup(tileID)?.activeFileDocumentReference?.url ?? fallbackURL
            let parent = currentURL.deletingLastPathComponent().lastPathComponent
            return SpotlightItemMetadata(
                item: item,
                title: currentURL.lastPathComponent,
                secondary: parent.isEmpty ? AppStrings.Spotlight.files : parent,
                group: parent.isEmpty ? AppStrings.Spotlight.files : parent,
                iconName: "doc.text",
                accentColor: nil
            )
        case let .browser(tileID, fallbackURL):
            let viewModel = resolver.browserViewModel(tileID)
            let currentURL = viewModel?.currentURL ?? fallbackURL
            let location = SpotlightSafeMetadata.browserLocation(currentURL)
            let normalizedTitle = viewModel?.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return SpotlightItemMetadata(
                item: item,
                title: normalizedTitle.isEmpty ? location.host : normalizedTitle,
                secondary: location.display,
                group: AppStrings.Spotlight.web,
                iconName: "globe",
                accentColor: nil
            )
        }
    }

    private static func terminalStatusLines(
        directoryURL: URL,
        activity: TerminalTabActivityState
    ) -> [String] {
        let directoryName = directoryURL.lastPathComponent
        return [
            activity.isActive ? AppStrings.Spotlight.active : AppStrings.Spotlight.idle,
            directoryName.isEmpty ? nil : directoryName,
        ].compactMap { $0 }
    }
}

/// Precomputed lookup and duplicate-title labels used by shelf and grid rendering.
@MainActor
struct SpotlightMetadataCatalog {
    let ordered: [SpotlightItemMetadata]
    let byID: [SpotlightPersistentItemID: SpotlightItemMetadata]
    let displayTitleByID: [SpotlightPersistentItemID: String]

    init(_ metadata: [SpotlightItemMetadata]) {
        ordered = metadata
        byID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: metadata) { "\($0.group)\u{0}\($0.title)" }
        var titles: [SpotlightPersistentItemID: String] = [:]
        for entries in grouped.values {
            for (index, entry) in entries.enumerated() {
                titles[entry.id] = entries.count == 1 ? entry.title : "\(entry.title) \(index + 1)"
            }
        }
        displayTitleByID = titles
    }

    func displayTitle(for entry: SpotlightItemMetadata) -> String {
        displayTitleByID[entry.id] ?? entry.title
    }
}

enum SpotlightSafeMetadata {
    struct BrowserLocation {
        let host: String
        let display: String
    }

    static func browserLocation(_ url: URL) -> BrowserLocation {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return BrowserLocation(host: AppStrings.Spotlight.web, display: AppStrings.Spotlight.web)
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let host = components.host.flatMap { $0.isEmpty ? nil : $0 } ?? AppStrings.Spotlight.web
        let path = components.percentEncodedPath
        let display = path.isEmpty || path == "/" ? host : host + path
        return BrowserLocation(host: host, display: display)
    }
}


@MainActor
final class SpotlightMetadataMonitor: ObservableObject {
    private var signature: [String] = []
    private var cancellables: [AnyCancellable] = []

    func configure(items: [SpotlightItem], resolver: SpotlightMetadataResolver) {
        var observed: [(String, AnyPublisher<Void, Never>)] = []
        for item in items {
            switch item {
            case let .file(tileID, _):
                if let group = resolver.fileGroup(tileID) {
                    observed.append((
                        "file:\(tileID.uuidString):\(ObjectIdentifier(group))",
                        group.objectWillChange.eraseToAnyPublisher()
                    ))
                }
            case let .browser(tileID, _):
                if let viewModel = resolver.browserViewModel(tileID) {
                    observed.append((
                        "browser:\(tileID.uuidString):\(ObjectIdentifier(viewModel))",
                        viewModel.objectWillChange.eraseToAnyPublisher()
                    ))
                }
            case .terminal, .standaloneTerminal, .vibeCast, .vibeLanes, .acp:
                break
            }
        }
        let nextSignature = observed.map(\.0)
        guard nextSignature != signature else { return }
        signature = nextSignature
        cancellables = observed.map { _, publisher in
            publisher.sink { [weak self] in self?.objectWillChange.send() }
        }
    }
}
