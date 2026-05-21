import Foundation

enum PaneWorkerExecutor {
    static let fileManager = FileManager.default
    static let directoryKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
    static let envExecutableURL = URL(fileURLWithPath: "/usr/bin/env")

    static func execute(pane: PaneWorkerKind, request: PaneWorkerRequest) -> PaneWorkerResponse {
        do {
            let value: String?
            switch pane {
            case .explorer:
                value = try handleExplorer(request)
            case .sourceControl:
                value = try handleSourceControl(request)
            case .editor:
                value = try handleEditor(request)
            case .terminal:
                value = try handleTerminal(request)
            }
            return PaneWorkerResponse(success: true, value: value, error: nil)
        } catch {
            return PaneWorkerResponse(success: false, value: nil, error: error.localizedDescription)
        }
    }

    static func handleExplorer(_ request: PaneWorkerRequest) throws -> String? {
        switch request.method {
        case .ping:
            return ISO8601DateFormatter().string(from: Date())

        case .listTree:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let rootURL = URL(fileURLWithPath: rootPath)
            let nodes = try loadImmediateChildren(of: rootURL)
            return try encodeJSONText(nodes)

        case .gitDiscoverRepositories:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let rootURL = URL(fileURLWithPath: rootPath)
            let payload = try discoverGitRepositories(
                for: rootURL,
                settings: decodeSourceControlSettings(from: request.arguments)
            )
            return try encodeJSONText(payload)

        case .gitDiscoverRepositoriesBatch:
            let rootPathsText = try requiredArgument("rootPaths", from: request.arguments)
            guard let rootPathsData = rootPathsText.data(using: .utf8) else {
                throw PaneWorkerError.invalidResponse
            }
            let rootPaths = try JSONDecoder().decode([String].self, from: rootPathsData)
            let payload = try discoverGitRepositoriesBatch(
                for: rootPaths.map(URL.init(fileURLWithPath:)),
                settings: decodeSourceControlSettings(from: request.arguments)
            )
            return try encodeJSONText(payload)

        case .gitRepositorySnapshot:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let rootURL = URL(fileURLWithPath: rootPath)
            let payload = try loadGitRepositorySnapshot(for: rootURL)
            return try encodeJSONText(payload)

        case .gitStatus:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let rootURL = URL(fileURLWithPath: rootPath)
            let payload = try loadGitStatus(for: rootURL)
            return try encodeJSONText(payload)

        case .gitBranches:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let rootURL = URL(fileURLWithPath: rootPath)
            let payload = try loadGitBranches(for: rootURL)
            return try encodeJSONText(payload)

        case .gitStage:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let relativePath = try requiredArgument("relativePath", from: request.arguments)
            try stageGitPath(for: URL(fileURLWithPath: rootPath), relativePath: relativePath)
            return nil

        case .gitUnstage:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let relativePath = try requiredArgument("relativePath", from: request.arguments)
            try unstageGitPath(for: URL(fileURLWithPath: rootPath), relativePath: relativePath)
            return nil

        case .gitUnstageAll:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            try unstageAllGitChanges(for: URL(fileURLWithPath: rootPath))
            return nil

        case .gitStageAll:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            try stageAllGitChanges(for: URL(fileURLWithPath: rootPath))
            return nil

        case .gitDiscard:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let relativePath = try requiredArgument("relativePath", from: request.arguments)
            try discardGitPath(for: URL(fileURLWithPath: rootPath), relativePath: relativePath)
            return nil

        case .gitDiscardAll:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            try discardAllGitChanges(for: URL(fileURLWithPath: rootPath))
            return nil

        case .gitCommit:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let message = try requiredArgument("message", from: request.arguments)
            try commitGitChanges(for: URL(fileURLWithPath: rootPath), message: message)
            return nil

        case .gitPush:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            try pushGitChanges(for: URL(fileURLWithPath: rootPath))
            return nil

        case .gitPull:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            try pullGitChanges(for: URL(fileURLWithPath: rootPath))
            return nil

        case .gitFetch:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            try fetchGitChanges(for: URL(fileURLWithPath: rootPath))
            return nil

        case .gitCheckoutBranch:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let branch = try requiredArgument("branch", from: request.arguments)
            let isRemote = request.arguments["isRemote"] == "1"
            try checkoutGitBranch(for: URL(fileURLWithPath: rootPath), branch: branch, isRemote: isRemote)
            return nil

        case .gitCommitHistory:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let historyLimit = Int(request.arguments["limit"] ?? "") ?? 100
            let payload = try loadGitCommitHistory(for: URL(fileURLWithPath: rootPath), limit: historyLimit)
            return try encodeJSONText(payload)

        case .gitFileHistory:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let relativePath = try requiredArgument("relativePath", from: request.arguments)
            let historyLimit = Int(request.arguments["limit"] ?? "") ?? 100
            let payload = try loadGitFileHistory(
                for: URL(fileURLWithPath: rootPath),
                relativePath: relativePath,
                limit: historyLimit
            )
            return try encodeJSONText(payload)

        case .gitFileContent:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let relativePath = try requiredArgument("relativePath", from: request.arguments)
            return try loadGitFileContent(
                for: URL(fileURLWithPath: rootPath),
                relativePath: relativePath
            )

        case .gitCurrentBranch:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let rootURL = URL(fileURLWithPath: rootPath)
            guard isGitAvailable(), isGitRepository(rootURL) else {
                return nil
            }
            return resolveCurrentBranchName(rootURL: rootURL)

        case .gitHubCloneOptions:
            let payload = try loadGitHubCloneOptions()
            return try encodeJSONText(payload)

        case .gitCloneRepository:
            let repositoryURL = try requiredArgument("repositoryURL", from: request.arguments)
            let destinationParentPath = try requiredArgument("destinationParentPath", from: request.arguments)
            let directoryName = request.arguments["directoryName"]
            let clonedURL = try cloneGitRepository(
                repositoryURL: repositoryURL,
                destinationParentURL: URL(fileURLWithPath: destinationParentPath),
                directoryName: directoryName
            )
            return clonedURL.path

        case .createFile:
            let directoryPath = try requiredArgument("directoryPath", from: request.arguments)
            let proposedName = request.arguments["name"] ?? "untitled"
            let created = try createItem(in: URL(fileURLWithPath: directoryPath), name: proposedName, isDirectory: false)
            return created.path

        case .createFolder:
            let directoryPath = try requiredArgument("directoryPath", from: request.arguments)
            let proposedName = request.arguments["name"] ?? "New Folder"
            let created = try createItem(in: URL(fileURLWithPath: directoryPath), name: proposedName, isDirectory: true)
            return created.path

        case .renameItem:
            let itemPath = try requiredArgument("itemPath", from: request.arguments)
            let newName = try requiredArgument("newName", from: request.arguments)
            let renamedPath = try renameItem(at: URL(fileURLWithPath: itemPath), toName: newName)
            return renamedPath.path

        case .moveItem:
            let sourcePath = try requiredArgument("sourcePath", from: request.arguments)
            let destinationDirectoryPath = try requiredArgument("destinationDirectoryPath", from: request.arguments)
            let destinationPath = try moveItem(
                at: URL(fileURLWithPath: sourcePath),
                toDirectory: URL(fileURLWithPath: destinationDirectoryPath)
            )
            return destinationPath.path

        case .copyItem:
            let sourcePath = try requiredArgument("sourcePath", from: request.arguments)
            let destinationDirectoryPath = try requiredArgument("destinationDirectoryPath", from: request.arguments)
            let destinationPath = try copyItem(
                at: URL(fileURLWithPath: sourcePath),
                toDirectory: URL(fileURLWithPath: destinationDirectoryPath)
            )
            return destinationPath.path

        case .deleteItem:
            let itemPath = try requiredArgument("itemPath", from: request.arguments)
            try fileManager.removeItem(at: URL(fileURLWithPath: itemPath))
            return nil

        case .readFile, .writeFile, .gitDiff:
            throw PaneWorkerError.workerFailure("Unsupported explorer worker method: \(request.method.rawValue)")
        }
    }

    static func handleSourceControl(_ request: PaneWorkerRequest) throws -> String? {
        switch request.method {
        case .ping:
            return ISO8601DateFormatter().string(from: Date())

        case .gitDiscoverRepositories, .gitDiscoverRepositoriesBatch, .gitRepositorySnapshot, .gitStatus, .gitBranches, .gitStage, .gitUnstage, .gitUnstageAll, .gitStageAll,
             .gitDiscard, .gitDiscardAll, .gitCommit, .gitPush, .gitPull, .gitFetch, .gitCheckoutBranch,
             .gitCommitHistory, .gitFileHistory, .gitFileContent, .gitCurrentBranch, .gitHubCloneOptions,
             .gitCloneRepository:
            return try handleExplorer(request)

        case .listTree, .createFile, .createFolder, .renameItem, .moveItem, .copyItem, .deleteItem,
             .readFile, .writeFile, .gitDiff:
            throw PaneWorkerError.workerFailure(
                "Unsupported source control worker method: \(request.method.rawValue)"
            )
        }
    }

    static func handleEditor(_ request: PaneWorkerRequest) throws -> String? {
        switch request.method {
        case .ping:
            return ISO8601DateFormatter().string(from: Date())

        case .readFile:
            let filePath = try requiredArgument("filePath", from: request.arguments)
            return try readTextFile(at: URL(fileURLWithPath: filePath))

        case .writeFile:
            let filePath = try requiredArgument("filePath", from: request.arguments)
            let content = request.arguments["content"] ?? ""
            let fileURL = URL(fileURLWithPath: filePath)
            guard let data = content.data(using: .utf8) else {
                throw PaneWorkerError.workerFailure("File encoding is not supported.")
            }
            try data.write(to: fileURL, options: [.atomic])
            return nil

        case .gitDiff:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let relativePath = try requiredArgument("relativePath", from: request.arguments)
            return try loadGitDiff(
                for: URL(fileURLWithPath: rootPath),
                relativePath: relativePath
            )

        case .listTree, .gitDiscoverRepositories, .gitDiscoverRepositoriesBatch, .gitRepositorySnapshot, .gitStatus, .gitBranches, .gitStage, .gitUnstage, .gitUnstageAll, .gitStageAll,
             .gitDiscard, .gitDiscardAll, .gitCommit, .gitPush, .gitPull, .gitFetch, .gitCheckoutBranch, .gitCommitHistory,
             .gitFileHistory, .gitFileContent, .gitCurrentBranch, .gitHubCloneOptions, .createFile, .createFolder, .renameItem,
             .moveItem, .copyItem, .deleteItem, .gitCloneRepository:
            throw PaneWorkerError.workerFailure("Unsupported editor worker method: \(request.method.rawValue)")
        }
    }

    static func handleTerminal(_ request: PaneWorkerRequest) throws -> String? {
        switch request.method {
        case .ping:
            return ISO8601DateFormatter().string(from: Date())
        case .gitCurrentBranch:
            let rootPath = try requiredArgument("rootPath", from: request.arguments)
            let rootURL = URL(fileURLWithPath: rootPath)
            guard isGitAvailable(), isGitRepository(rootURL) else {
                return nil
            }
            return resolveCurrentBranchName(rootURL: rootURL)
        default:
            throw PaneWorkerError.workerFailure("Unsupported terminal worker method: \(request.method.rawValue)")
        }
    }
}

private extension PaneWorkerExecutor {
    static func decodeSourceControlSettings(
        from arguments: [String: String]
    ) throws -> VibeSpaceSourceControlSettings {
        guard let settingsText = arguments["sourceControlSettings"],
              !settingsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .default
        }

        guard let data = settingsText.data(using: .utf8) else {
            throw PaneWorkerError.invalidResponse
        }

        return try JSONDecoder().decode(VibeSpaceSourceControlSettings.self, from: data).normalized()
    }
}
