import Foundation
import os.signpost

// MARK: - Operation Record

struct OperationRecord: Sendable {
    let id: UUID
    let traceID: UUID?
    let parentID: UUID?
    let operationName: String
    let paneKind: String?
    let projectContext: String?
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let succeeded: Bool
    let errorDescription: String?
}

// MARK: - Aggregation

struct OperationAggregate: Sendable {
    let key: String
    var count: Int = 0
    var totalDuration: TimeInterval = 0
    var maxDuration: TimeInterval = 0
    var failureCount: Int = 0

    var averageDuration: TimeInterval { count > 0 ? totalDuration / Double(count) : 0 }

    mutating func incorporate(_ record: OperationRecord) {
        count += 1
        totalDuration += record.duration
        if record.duration > maxDuration { maxDuration = record.duration }
        if !record.succeeded { failureCount += 1 }
    }
}

// MARK: - Metrics Store

final class OperationMetricsStore: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var buffer: [OperationRecord?]
    private var state: (head: Int, count: Int)
    private var traceStack: [(id: UUID, parentID: UUID, name: String, projectContext: String?, startTime: Date)]

    static let signpostLog = OSLog(subsystem: AppDiagnostics.subsystem, category: "operation.metrics")

    init(capacity: Int = 500) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
        self.state = (head: 0, count: 0)
        self.traceStack = []
    }

    func record(_ record: OperationRecord) {
        lock.lock()
        defer { lock.unlock() }
        let writeIndex = (state.head + state.count) % capacity
        buffer[writeIndex] = record
        if state.count < capacity {
            state.count += 1
        } else {
            state.head = (state.head + 1) % capacity
        }
    }

    func snapshot() -> [OperationRecord] {
        lock.lock()
        defer { lock.unlock() }
        let snapshotState = state
        var result: [OperationRecord] = []
        result.reserveCapacity(snapshotState.count)
        for i in 0..<snapshotState.count {
            if let r = buffer[(snapshotState.head + i) % capacity] {
                result.append(r)
            }
        }
        return result
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.count
    }

    // MARK: - Ambient Trace

    /// Begin a trace. All operations recorded until the matching `endTrace` are
    /// children of this trace. Supports nesting. Works across Task boundaries.
    private static let maxTraceDepth = 32
    private static let staleTraceTimeout: TimeInterval = 300 // 5 minutes

    @discardableResult
    func beginTrace(name: String, projectContext: String? = nil) -> UUID {
        let traceID = UUID()
        let parentID = UUID()
        lock.lock()
        let now = Date()
        traceStack.removeAll { now.timeIntervalSince($0.startTime) > Self.staleTraceTimeout }
        if traceStack.count >= Self.maxTraceDepth {
            lock.unlock()
            return traceID
        }
        traceStack.append((id: traceID, parentID: parentID, name: name, projectContext: projectContext, startTime: now))
        lock.unlock()
        return traceID
    }

    func endTrace() {
        lock.lock()
        let trace = traceStack.isEmpty ? nil : traceStack.removeLast()
        let parentParentID = traceStack.last?.parentID
        lock.unlock()
        guard let trace else { return }
        let now = Date()
        let parent = OperationRecord(
            id: trace.parentID,
            traceID: trace.id,
            parentID: parentParentID,
            operationName: trace.name,
            paneKind: nil,
            projectContext: trace.projectContext,
            startTime: trace.startTime,
            endTime: now,
            duration: now.timeIntervalSince(trace.startTime),
            succeeded: true,
            errorDescription: nil
        )
        record(parent)
    }

    // MARK: - Convenience Recording

    func recordOperation(
        name: String,
        paneKind: String? = nil,
        projectContext: String? = nil,
        startTime: Date,
        endTime: Date = Date(),
        succeeded: Bool = true,
        errorDescription: String? = nil
    ) {
        lock.lock()
        let trace = traceStack.last
        lock.unlock()
        let record = OperationRecord(
            id: UUID(),
            traceID: trace?.id,
            parentID: trace?.parentID,
            operationName: name,
            paneKind: paneKind,
            projectContext: projectContext ?? trace?.projectContext,
            startTime: startTime,
            endTime: endTime,
            duration: endTime.timeIntervalSince(startTime),
            succeeded: succeeded,
            errorDescription: errorDescription
        )
        self.record(record)
    }

    // MARK: - Aggregation

    func aggregateByOperation() -> [String: OperationAggregate] {
        let records = snapshot()
        var result: [String: OperationAggregate] = [:]
        for record in records {
            var agg = result[record.operationName] ?? OperationAggregate(key: record.operationName)
            agg.incorporate(record)
            result[record.operationName] = agg
        }
        return result
    }

    func aggregateByProject() -> [String: OperationAggregate] {
        let records = snapshot()
        var result: [String: OperationAggregate] = [:]
        for record in records {
            let key = record.projectContext ?? "none"
            var agg = result[key] ?? OperationAggregate(key: key)
            agg.incorporate(record)
            result[key] = agg
        }
        return result
    }

    // MARK: - Export

    func exportPayload() -> OperationMetricsPayload {
        OperationMetricsPayload(
            records: snapshot().map(CodableOperationRecord.init),
            byOperation: aggregateByOperation().mapValues(CodableOperationAggregate.init),
            byProject: aggregateByProject().mapValues(CodableOperationAggregate.init)
        )
    }
}

// MARK: - Codable Export Types

struct CodableOperationRecord: Codable {
    let id: String
    let traceID: String?
    let parentID: String?
    let operationName: String
    let paneKind: String?
    let projectContext: String?
    let startTime: String
    let endTime: String
    let duration: TimeInterval
    let succeeded: Bool
    let errorDescription: String?

    init(_ r: OperationRecord) {
        id = r.id.uuidString
        traceID = r.traceID?.uuidString
        parentID = r.parentID?.uuidString
        operationName = r.operationName
        paneKind = r.paneKind
        projectContext = r.projectContext
        startTime = AppDiagnostics.iso8601Timestamp(r.startTime)
        endTime = AppDiagnostics.iso8601Timestamp(r.endTime)
        duration = r.duration
        succeeded = r.succeeded
        errorDescription = r.errorDescription
    }
}

struct CodableOperationAggregate: Codable {
    let key: String
    let count: Int
    let totalDuration: TimeInterval
    let maxDuration: TimeInterval
    let averageDuration: TimeInterval
    let failureCount: Int

    init(_ a: OperationAggregate) {
        key = a.key
        count = a.count
        totalDuration = a.totalDuration
        maxDuration = a.maxDuration
        averageDuration = a.averageDuration
        failureCount = a.failureCount
    }
}

struct OperationMetricsPayload: Codable {
    let records: [CodableOperationRecord]
    let byOperation: [String: CodableOperationAggregate]
    let byProject: [String: CodableOperationAggregate]
}
