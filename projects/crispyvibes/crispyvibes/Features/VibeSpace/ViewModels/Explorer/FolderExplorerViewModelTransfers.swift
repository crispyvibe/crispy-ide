import Foundation

extension FolderExplorerViewModel {
    func moveItem(at sourcePath: String, toDirectory destinationDirectoryPath: String) {
        transferItems(
            using: [
                ExplorerItemTransferPlan(
                    sourceURL: URL(fileURLWithPath: sourcePath),
                    targetDirectoryURL: URL(fileURLWithPath: destinationDirectoryPath),
                    operation: .move
                )
            ]
        )
    }

    func copyItem(at sourcePath: String, toDirectory destinationDirectoryPath: String) {
        transferItems(
            using: [
                ExplorerItemTransferPlan(
                    sourceURL: URL(fileURLWithPath: sourcePath),
                    targetDirectoryURL: URL(fileURLWithPath: destinationDirectoryPath),
                    operation: .copy
                )
            ]
        )
    }

    func transferItems(using plans: [ExplorerItemTransferPlan]) {
        guard !plans.isEmpty else { return }

        let normalizedPlans = plans.map {
            ExplorerItemTransferPlan(
                sourceURL: $0.sourceURL.standardizedFileURL,
                targetDirectoryURL: $0.targetDirectoryURL.standardizedFileURL,
                operation: $0.operation
            )
        }

        workerStatus = .busy(progressTitle(for: normalizedPlans))

        Task { [weak self] in
            guard let self else { return }
            do {
                var directoriesToRefresh: Set<URL> = []

                for plan in normalizedPlans {
                    let resultingPath = try await self.worker.execute(
                        plan.operation.workerMethod,
                        arguments: [
                            "sourcePath": plan.sourceURL.path,
                            "destinationDirectoryPath": plan.targetDirectoryURL.path
                        ],
                        timeout: 20
                    )

                    guard let resultingPath, !resultingPath.isEmpty else {
                        throw PaneWorkerError.invalidResponse
                    }

                    if plan.operation == .move {
                        let destinationURL = URL(fileURLWithPath: resultingPath)
                        self.updateSelections(afterMoving: plan.sourceURL, to: destinationURL)
                        if let rootURL = self.rootURL,
                           self.isSamePathOrDescendant(plan.sourceURL, of: rootURL) {
                            directoriesToRefresh.insert(plan.sourceURL.deletingLastPathComponent())
                        }
                    }
                    directoriesToRefresh.insert(plan.targetDirectoryURL)
                }

                for directoryURL in directoriesToRefresh.sorted(by: { $0.path < $1.path }) {
                    _ = await self.refreshDirectoryContents(
                        at: directoryURL,
                        showLoadingState: false
                    )
                }
            } catch {
                let title = normalizedPlans.first?.operation.failureTitle ?? "Transfer"
                self.userFacingError = "\(title) failed: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Explorer worker unavailable")
            }
        }
    }

    private func progressTitle(for plans: [ExplorerItemTransferPlan]) -> String {
        guard let operation = ExplorerItemDropPlanner.uniformOperation(for: plans) else {
            return "Organizing"
        }
        return operation.progressTitle
    }
}
