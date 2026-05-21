import Foundation
import os.signpost

// MARK: - Stable Debug IDs

@MainActor
enum TerminalDebugID {
    private static var nextSessionID: Int = 1
    private static var nextSurfaceID: Int = 1

    static func nextSession() -> Int {
        defer { nextSessionID += 1 }
        return nextSessionID
    }

    static func nextSurface() -> Int {
        defer { nextSurfaceID += 1 }
        return nextSurfaceID
    }
}

// MARK: - Lifecycle Event Types

enum TerminalLifecycleEvent: String, Codable {
    case sessionCreate = "session.create"
    case sessionTerminate = "session.terminate"
    case surfaceCreate = "surface.create"
    case surfaceDestroy = "surface.destroy"
    case hostAttach = "host.attach"
    case hostDetach = "host.detach"
    case surfaceOcclude = "surface.occlude"
    case surfaceUnocclude = "surface.unocclude"
    case surfaceResize = "surface.resize"
    case surfaceFocus = "surface.focus"
    case surfaceBlur = "surface.blur"
}

enum TerminalPresentationSource: String, Codable {
    case detailed
    case stacked
    case split
    case rail
    case board
    case spotlight
    case transient
    case unknown
}

enum TerminalLifecycleReason: String, Codable, Hashable {
    case initial
    case rendererUnhealthy
    case terminate
}

// MARK: - Logger

@MainActor
enum TerminalLifecycleLogger {
    static func log(
        event: TerminalLifecycleEvent,
        sessionDebugID: Int?,
        surfaceDebugID: Int?,
        sessionID: UUID? = nil,
        vibespaceID: UUID? = nil,
        source: TerminalPresentationSource = .unknown,
        reason: TerminalLifecycleReason = .initial,
        pixelWidth: UInt32? = nil,
        pixelHeight: UInt32? = nil,
        backingScale: Double? = nil,
        extra: [String: String] = [:]
    ) {
        var metadata: [String: String] = [
            "event": event.rawValue,
            "source": source.rawValue,
            "reason": reason.rawValue
        ]
        if let sid = sessionDebugID { metadata["sessionDebugID"] = "S\(sid)" }
        if let sfid = surfaceDebugID { metadata["surfaceDebugID"] = "SF\(sfid)" }
        if let id = sessionID { metadata["sessionID"] = id.uuidString }
        if let wid = vibespaceID { metadata["vibespaceID"] = wid.uuidString }
        if let w = pixelWidth { metadata["pixelWidth"] = String(w) }
        if let h = pixelHeight { metadata["pixelHeight"] = String(h) }
        if let s = backingScale { metadata["backingScale"] = String(format: "%.1f", s) }
        for (k, v) in extra { metadata[k] = v }

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .info,
            event: event.rawValue,
            metadata: metadata
        )

        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalLifecycle",
            "%{public}@ S%d SF%d source=%{public}@ reason=%{public}@",
            event.rawValue,
            sessionDebugID ?? 0,
            surfaceDebugID ?? 0,
            source.rawValue,
            reason.rawValue
        )
    }

    // MARK: - Anomaly Assertions

    static func assertSurfaceDestroyedOnTerminate(
        sessionDebugID: Int,
        surfaceExists: Bool
    ) {
        if surfaceExists {
            let msg = "ANOMALY: session S\(sessionDebugID) terminated but surface still exists"
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .error,
                event: "anomaly.surface_outlived_session",
                metadata: ["sessionDebugID": "S\(sessionDebugID)"]
            )
            assertionFailure(msg)
        }
    }

    static func assertPollingNotRunningWhileHidden(
        sessionDebugID: Int,
        hasWindow: Bool,
        isVisible: Bool
    ) {
        if !hasWindow || !isVisible {
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .error,
                event: "anomaly.polling_while_hidden",
                metadata: [
                    "sessionDebugID": "S\(sessionDebugID)",
                    "hasWindow": String(hasWindow),
                    "isVisible": String(isVisible)
                ]
            )
        }
    }

    static func assertStandaloneRegistryEmpty(
        vibespaceID: UUID?,
        remainingCount: Int
    ) {
        if remainingCount > 0 {
            let wid = vibespaceID?.uuidString ?? "nil"
            let msg = "ANOMALY: vibespace \(wid) closed but \(remainingCount) standalone VMs remain"
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .error,
                event: "anomaly.standalone_vms_after_close",
                metadata: [
                    "vibespaceID": wid,
                    "remainingCount": String(remainingCount)
                ]
            )
            assertionFailure(msg)
        }
    }
}
