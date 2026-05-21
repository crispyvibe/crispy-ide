import Foundation
import os.signpost

actor MeasuredPaneWorker: PaneWorkerExecuting {
    private let inner: any PaneWorkerExecuting
    private let metricsStore: OperationMetricsStore
    private let kind: PaneWorkerKind

    init(inner: any PaneWorkerExecuting, metricsStore: OperationMetricsStore, kind: PaneWorkerKind) {
        self.inner = inner
        self.metricsStore = metricsStore
        self.kind = kind
    }

    func restart() async {
        await inner.restart()
    }

    func execute(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval
    ) async throws -> String? {
        let name = method.rawValue
        let spID = OSSignpostID(log: OperationMetricsStore.signpostLog)
        os_signpost(.begin, log: OperationMetricsStore.signpostLog, name: "PaneWorkerExecute", signpostID: spID, "%{public}s", name)

        let startTime = Date()
        let projectContext = arguments["rootPath"] ?? arguments["path"]
        do {
            let result = try await inner.execute(method, arguments: arguments, timeout: timeout)
            os_signpost(.end, log: OperationMetricsStore.signpostLog, name: "PaneWorkerExecute", signpostID: spID)
            metricsStore.recordOperation(name: name, paneKind: kind.rawValue, projectContext: projectContext, startTime: startTime)
            return result
        } catch {
            os_signpost(.end, log: OperationMetricsStore.signpostLog, name: "PaneWorkerExecute", signpostID: spID)
            metricsStore.recordOperation(name: name, paneKind: kind.rawValue, projectContext: projectContext, startTime: startTime, succeeded: false, errorDescription: error.localizedDescription)
            throw error
        }
    }
}
