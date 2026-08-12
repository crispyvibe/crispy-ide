import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticsEventStoreEvictsOldEntries() {
        let store = DiagnosticsEventStore(maxEvents: 2)
        store.append(DiagnosticsEventRecord(timestamp: "1", category: "c", level: "i", event: "a", metadata: [:]))
        store.append(DiagnosticsEventRecord(timestamp: "2", category: "c", level: "i", event: "b", metadata: [:]))
        store.append(DiagnosticsEventRecord(timestamp: "3", category: "c", level: "i", event: "c", metadata: [:]))

        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot.first?.event, "b")
        XCTAssertEqual(snapshot.last?.event, "c")
    }

    func testAppDiagnosticsHashAndPathTokenAreDeterministic() {
        let value = "/tmp/some/path"
        let hash1 = AppDiagnostics.sha256Hex(value)
        let hash2 = AppDiagnostics.sha256Hex(value)
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 64)

        let token = AppDiagnostics.pathToken(value)
        XCTAssertTrue(token.hasPrefix("path#"))
        XCTAssertEqual(token.count, 17)
    }

    func testAppDiagnosticsRecordStoresInfoEvents() {
        let eventName = "unit-test-event-\(UUID().uuidString)"
        AppDiagnostics.record(
            category: .vibespaceLifecycle,
            level: .info,
            event: eventName,
            metadata: ["k": "v"]
        )

        let snapshot = AppDiagnostics.eventStore.snapshot()
        XCTAssertTrue(snapshot.contains(where: { $0.event == eventName && $0.metadata["k"] == "v" }))
    }

    func testAppDiagnosticsDebugEventsRespectEnvironmentFlag() {
        let key = AppDiagnostics.deepDiagnosticsEnvironmentKey
        let original = ProcessInfo.processInfo.environment[key]
        defer {
            if let original {
                setenv(key, original, 1)
            } else {
                unsetenv(key)
            }
        }

        let beforeCount = AppDiagnostics.eventStore.snapshot().count
        unsetenv(key)
        AppDiagnostics.record(
            category: .terminalHost,
            level: .debug,
            event: "debug-disabled-\(UUID().uuidString)"
        )
        let afterDisabledCount = AppDiagnostics.eventStore.snapshot().count
        XCTAssertEqual(afterDisabledCount, beforeCount)

        setenv(key, "1", 1)
        let enabledEvent = "debug-enabled-\(UUID().uuidString)"
        AppDiagnostics.record(
            category: .terminalHost,
            level: .debug,
            event: enabledEvent
        )
        let snapshot = AppDiagnostics.eventStore.snapshot()
        XCTAssertTrue(snapshot.contains(where: { $0.event == enabledEvent }))
    }

    func testAppDiagnosticsRecordsMultipleCategoriesAndLevels() {
        let terminalEvent = "terminal-event-\(UUID().uuidString)"
        let hostEvent = "host-event-\(UUID().uuidString)"
        let faultEvent = "fault-event-\(UUID().uuidString)"

        AppDiagnostics.record(category: .terminalLifecycle, level: .notice, event: terminalEvent)
        AppDiagnostics.record(category: .terminalHost, level: .error, event: hostEvent)
        AppDiagnostics.record(category: .vibespaceLifecycle, level: .fault, event: faultEvent)
        AppDiagnostics.hostDebug("redacted debug message")

        let snapshot = AppDiagnostics.eventStore.snapshot()
        XCTAssertTrue(snapshot.contains(where: { $0.event == terminalEvent && $0.category == DiagnosticsCategory.terminalLifecycle.rawValue }))
        XCTAssertTrue(snapshot.contains(where: { $0.event == hostEvent && $0.level == DiagnosticsLevel.error.rawValue }))
        XCTAssertTrue(snapshot.contains(where: { $0.event == faultEvent && $0.level == DiagnosticsLevel.fault.rawValue }))
    }

    func testDiagnosticsExportServiceWritesSanitizedPayload() throws {
        let defaults = UserDefaults.standard
        let keyAppearance = AppPreferences.appearancePreferenceKey
        let keyPresetMode = AppPreferences.terminalPresetLaunchModeKey

        try withUserDefaultsSnapshot(keys: [keyAppearance, keyPresetMode], defaults: defaults) {
            defaults.set("light", forKey: keyAppearance)
            defaults.set("standard", forKey: keyPresetMode)

            let exportRoot = try makeTempDirectory(prefix: "crispyvibes-diagnostics-export")
            defer { try? FileManager.default.removeItem(at: exportRoot) }
            let destination = exportRoot.appendingPathComponent("diagnostics.json")
            let persistenceStore = VibeSpacePersistenceStore(
                store: AppPersistenceDataStore(fileManager: .default, appDirectoryURL: exportRoot)
            )

            let previousEventCount = AppDiagnostics.eventStore.snapshot().count
            let exportedEventCount = try DiagnosticsExportService.export(
                to: destination,
                using: persistenceStore
            )
            XCTAssertGreaterThanOrEqual(exportedEventCount, previousEventCount)
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

            let raw = try String(contentsOf: destination, encoding: .utf8)
            let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])

            let defaultsSnapshot = try XCTUnwrap(jsonObject["defaultsSnapshot"] as? [String: Any])
            XCTAssertEqual(defaultsSnapshot[AppPreferences.appearancePreferenceKey] as? String, "light")
            XCTAssertEqual(defaultsSnapshot[AppPreferences.terminalPresetLaunchModeKey] as? String, "standard")
        }
    }

    func testDiagnosticsExportServiceThrowsWhenDestinationDirectoryIsMissing() throws {
        let exportRoot = try makeTempDirectory(prefix: "crispyvibes-diagnostics-missing-destination")
        defer { try? FileManager.default.removeItem(at: exportRoot) }
        let destination = exportRoot
            .appendingPathComponent("missing-directory", isDirectory: true)
            .appendingPathComponent("diagnostics.json")
        let persistenceStore = VibeSpacePersistenceStore(
            store: AppPersistenceDataStore(fileManager: .default, appDirectoryURL: exportRoot)
        )

        XCTAssertThrowsError(try DiagnosticsExportService.export(to: destination, using: persistenceStore))
    }

    func testAppDiagnosticsTimestampFormattingUsesFractionalSeconds() {
        let timestamp = AppDiagnostics.iso8601Timestamp(Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(timestamp.contains("T"))
        XCTAssertTrue(timestamp.contains("."))
        XCTAssertTrue(timestamp.contains("Z"))
    }

    func testAppDelegateRegistersServicesOnLaunchCallbacks() {
        let delegate = AppDelegate()
        // This test exercises the real launch path, so opt out of the guard
        // that skips launch side effects under XCTest.
        delegate.isRunningUnitTests = false
        NSApp.servicesProvider = nil

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let provider = NSApp.servicesProvider as AnyObject?
        XCTAssertTrue(provider?.responds(to: NSSelectorFromString("rephrase:userData:error:")) == true)
        XCTAssertTrue(provider?.responds(to: NSSelectorFromString("research:userData:error:")) == true)
    }
}
