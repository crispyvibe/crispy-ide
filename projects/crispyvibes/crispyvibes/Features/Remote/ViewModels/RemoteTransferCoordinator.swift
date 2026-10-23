import AppKit
import Foundation

@MainActor
final class RemoteTransferCoordinator: ObservableObject {
    struct Operation: Identifiable, Equatable {
        enum Mode: Equatable {
            case download
            case externalOpen
        }

        enum State: Equatable {
            case preparing
            case transferring
            case cancelling
            case publishing
            case completed
            case failed(String)
        }

        let id: UUID
        let mode: Mode
        let title: String
        var state: State
        var completedBytes: UInt64
        var totalBytes: UInt64
        var completedFiles: Int
        var totalFiles: Int
        var currentItem: String?
        var localURL: URL?

        var fractionCompleted: Double? {
            guard totalBytes > 0 else { return nil }
            return min(1, Double(completedBytes) / Double(totalBytes))
        }
    }

    @Published private(set) var operation: Operation?
    @Published var errorMessage: String?

    private let interaction: VibeSpaceInteractionService
    private var operationTask: Task<Void, Never>?

    init(interaction: VibeSpaceInteractionService) {
        self.interaction = interaction
    }

    func requestDownload(
        item: RemoteTransferItem,
        projectName: String,
        using service: any RemoteItemTransferring
    ) {
        guard operationTask == nil, operation == nil else {
            errorMessage = AppStrings.RemoteTransfer.alreadyInProgress
            return
        }

        let panel = NSSavePanel()
        panel.title = AppStrings.RemoteTransfer.downloadTitle
        panel.prompt = AppStrings.RemoteTransfer.download
        panel.nameFieldStringValue = item.displayName
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        start(
            item: item,
            projectName: projectName,
            mode: .download,
            service: service,
            destinationURL: destinationURL
        )
    }

    func requestExternalOpen(
        item: RemoteTransferItem,
        projectName: String,
        using service: any RemoteItemTransferring
    ) {
        guard operationTask == nil, operation == nil else {
            errorMessage = AppStrings.RemoteTransfer.alreadyInProgress
            return
        }
        start(
            item: item,
            projectName: projectName,
            mode: .externalOpen,
            service: service,
            destinationURL: nil
        )
    }

    func cancel() {
        guard let state = operation?.state else { return }
        switch state {
        case .preparing, .transferring:
            operation?.state = .cancelling
            operationTask?.cancel()
        case .cancelling, .publishing, .completed, .failed:
            break
        }
    }

    func dismissCompleted() {
        guard let state = operation?.state else { return }
        switch state {
        case .completed, .failed:
            operation = nil
        case .preparing, .transferring, .cancelling, .publishing:
            break
        }
    }

    func requestLocalOpen(_ url: URL) {
        guard interaction.open(url) else {
            errorMessage = AppStrings.Editor.systemApplicationLaunchFailed
            return
        }
    }

    func showCompletedItemInFinder() {
        guard let localURL = operation?.localURL else { return }
        interaction.revealInFinder(localURL)
    }

    func clearError() {
        errorMessage = nil
    }

    private func start(
        item: RemoteTransferItem,
        projectName: String,
        mode: Operation.Mode,
        service: any RemoteItemTransferring,
        destinationURL: URL?
    ) {
        let operationID = UUID()
        operation = Operation(
            id: operationID,
            mode: mode,
            title: mode == .download
                ? AppStrings.RemoteTransfer.downloading(item.displayName)
                : AppStrings.RemoteTransfer.preparingToOpen(item.displayName),
            state: .preparing,
            completedBytes: 0,
            totalBytes: 0,
            completedFiles: 0,
            totalFiles: 0,
            currentItem: projectName,
            localURL: nil
        )
        AppDiagnostics.record(
            category: .remote,
            level: .info,
            event: "remote_transfer_started",
            metadata: [
                "mode": mode == .download ? "download" : "external_open",
                "project_token": AppDiagnostics.pathToken(projectName),
                "kind": item.isDirectory ? "directory" : "file"
            ]
        )

        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let progress: @Sendable (RemoteTransferProgress) -> Void = { [weak self] update in
                    if update.phase == .publishing {
                        let applied = DispatchSemaphore(value: 0)
                        Task { @MainActor [weak self] in
                            self?.apply(update, operationID: operationID)
                            applied.signal()
                        }
                        applied.wait()
                    } else {
                        Task { @MainActor [weak self] in
                            self?.apply(update, operationID: operationID)
                        }
                    }
                }
                let receipt: RemoteTransferReceipt
                switch mode {
                case .download:
                    guard let destinationURL else { return }
                    receipt = try await service.download(item, to: destinationURL, progress: progress)
                case .externalOpen:
                    receipt = try await service.materializeForExternalOpen(item, progress: progress)
                }
                if mode == .externalOpen,
                   !interaction.open(receipt.localURL) {
                    try? FileManager.default.removeItem(at: receipt.localURL.deletingLastPathComponent())
                    throw ExternalFileOpenError.launchFailed
                }
                complete(receipt, operationID: operationID)
            } catch is CancellationError {
                clear(operationID: operationID)
            } catch {
                if Task.isCancelled {
                    clear(operationID: operationID)
                } else {
                    fail(error, operationID: operationID)
                }
            }
        }
    }

    private func apply(_ progress: RemoteTransferProgress, operationID: UUID) {
        guard operation?.id == operationID,
              operation?.state != .cancelling else { return }
        switch progress.phase {
        case .preparing:
            operation?.state = .preparing
        case .transferring:
            operation?.state = .transferring
        case .publishing:
            operation?.state = .publishing
        }
        operation?.completedBytes = progress.completedBytes
        operation?.totalBytes = progress.totalBytes
        operation?.completedFiles = progress.completedFiles
        operation?.totalFiles = progress.totalFiles
        operation?.currentItem = progress.currentItem
    }

    private func complete(_ receipt: RemoteTransferReceipt, operationID: UUID) {
        guard operation?.id == operationID else { return }
        operation?.state = .completed
        operation?.localURL = receipt.localURL
        operationTask = nil
        AppDiagnostics.record(
            category: .remote,
            level: .info,
            event: "remote_transfer_completed",
            metadata: ["temporary": receipt.isTemporary ? "true" : "false"]
        )
    }

    private func clear(operationID: UUID) {
        guard operation?.id == operationID else { return }
        operation = nil
        operationTask = nil
        AppDiagnostics.record(
            category: .remote,
            level: .info,
            event: "remote_transfer_cancelled"
        )
    }

    private func fail(_ error: Error, operationID: UUID) {
        guard operation?.id == operationID else { return }
        operation?.state = .failed(error.localizedDescription)
        operation?.currentItem = nil
        operationTask = nil
        AppDiagnostics.record(
            category: .remote,
            level: .error,
            event: "remote_transfer_failed",
            metadata: ["error": String(error.localizedDescription.prefix(200))]
        )
    }
}
