import AppKit
import Foundation

enum ExplorerItemTransferOperation: String, Equatable {
    case move
    case copy

    var workerMethod: PaneWorkerMethod {
        switch self {
        case .move:
            return .moveItem
        case .copy:
            return .copyItem
        }
    }

    var dragOperation: NSDragOperation {
        switch self {
        case .move:
            return .move
        case .copy:
            return .copy
        }
    }

    var progressTitle: String {
        switch self {
        case .move:
            return "Moving"
        case .copy:
            return "Copying"
        }
    }

    var failureTitle: String {
        switch self {
        case .move:
            return "Move"
        case .copy:
            return "Copy"
        }
    }
}

struct ExplorerItemTransferPlan: Equatable {
    let sourceURL: URL
    let targetDirectoryURL: URL
    let operation: ExplorerItemTransferOperation

    var destinationURL: URL {
        targetDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    }
}

enum ExplorerItemDropPlanner {
    static func dragOperation(
        for pasteboard: NSPasteboard,
        targetDirectoryURL: URL,
        projectRootURLs: [URL]
    ) -> NSDragOperation {
        let plans = planDrop(from: pasteboard, targetDirectoryURL: targetDirectoryURL, projectRootURLs: projectRootURLs)
        guard let operation = uniformOperation(for: plans) else {
            return []
        }
        return operation.dragOperation
    }

    static func planDrop(
        from pasteboard: NSPasteboard,
        targetDirectoryURL: URL,
        projectRootURLs: [URL]
    ) -> [ExplorerItemTransferPlan] {
        let sourceURLs = VibeSpaceDragPayloadDecoder.urls(from: pasteboard)
        return plans(for: sourceURLs, targetDirectoryURL: targetDirectoryURL, projectRootURLs: projectRootURLs)
    }

    static func loadPlans(
        from providers: [NSItemProvider],
        targetDirectoryURL: URL,
        projectRootURLs: [URL],
        completion: @escaping ([ExplorerItemTransferPlan]) -> Void
    ) {
        VibeSpaceDragPayloadDecoder.loadURLs(from: providers) { sourceURLs in
            completion(
                plans(
                    for: sourceURLs,
                    targetDirectoryURL: targetDirectoryURL,
                    projectRootURLs: projectRootURLs
                )
            )
        }
    }

    static func plans(
        for sourceURLs: [URL],
        targetDirectoryURL: URL,
        projectRootURLs: [URL]
    ) -> [ExplorerItemTransferPlan] {
        let normalizedTargetDirectoryURL = targetDirectoryURL.standardizedFileURL
        guard isExistingDirectory(at: normalizedTargetDirectoryURL) else {
            return []
        }

        return sourceURLs.compactMap { sourceURL in
            plan(
                sourceURL: sourceURL,
                targetDirectoryURL: normalizedTargetDirectoryURL,
                projectRootURLs: projectRootURLs
            )
        }
    }

    static func uniformOperation(
        for plans: [ExplorerItemTransferPlan]
    ) -> ExplorerItemTransferOperation? {
        guard let firstOperation = plans.first?.operation else {
            return nil
        }
        return plans.allSatisfy { $0.operation == firstOperation } ? firstOperation : nil
    }

    private static func plan(
        sourceURL: URL,
        targetDirectoryURL: URL,
        projectRootURLs: [URL]
    ) -> ExplorerItemTransferPlan? {
        let normalizedSourceURL = sourceURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalizedSourceURL.path) else {
            return nil
        }

        let operation = resolveOperation(
            sourceURL: normalizedSourceURL,
            targetDirectoryURL: targetDirectoryURL,
            projectRootURLs: projectRootURLs
        )
        let destinationURL = targetDirectoryURL.appendingPathComponent(normalizedSourceURL.lastPathComponent)

        guard destinationURL.standardizedFileURL.path != normalizedSourceURL.path else {
            return nil
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return nil
        }

        if isDirectory(at: normalizedSourceURL),
           isDescendant(candidate: targetDirectoryURL, of: normalizedSourceURL) {
            return nil
        }

        return ExplorerItemTransferPlan(
            sourceURL: normalizedSourceURL,
            targetDirectoryURL: targetDirectoryURL,
            operation: operation
        )
    }

    private static func resolveOperation(
        sourceURL: URL,
        targetDirectoryURL: URL,
        projectRootURLs: [URL]
    ) -> ExplorerItemTransferOperation {
        let normalizedRoots = projectRootURLs.map(\.standardizedFileURL)
        let sourceProjectRoot = longestMatchingProjectRoot(for: sourceURL, in: normalizedRoots)
        let targetProjectRoot = longestMatchingProjectRoot(for: targetDirectoryURL, in: normalizedRoots)

        if let sourceProjectRoot, let targetProjectRoot {
            return sourceProjectRoot.path == targetProjectRoot.path ? .move : .copy
        }

        return .copy
    }

    private static func longestMatchingProjectRoot(
        for url: URL,
        in projectRootURLs: [URL]
    ) -> URL? {
        projectRootURLs
            .filter { isSamePathOrDescendant(url, of: $0) }
            .max { lhs, rhs in
                lhs.path.count < rhs.path.count
            }
    }

    private static func isExistingDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isSamePathOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let normalizedCandidate = candidate.standardizedFileURL.path
        let normalizedAncestor = ancestor.standardizedFileURL.path
        if normalizedCandidate == normalizedAncestor {
            return true
        }
        let prefix = normalizedAncestor.hasSuffix("/") ? normalizedAncestor : normalizedAncestor + "/"
        return normalizedCandidate.hasPrefix(prefix)
    }

    private static func isDescendant(candidate: URL, of ancestor: URL) -> Bool {
        let normalizedCandidate = candidate.standardizedFileURL.path
        let normalizedAncestor = ancestor.standardizedFileURL.path
        let prefix = normalizedAncestor.hasSuffix("/") ? normalizedAncestor : normalizedAncestor + "/"
        return normalizedCandidate.hasPrefix(prefix)
    }
}
