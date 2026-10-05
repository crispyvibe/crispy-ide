import Foundation
import XCTest
@testable import CrispyVibes

/// Guards the source-level ownership and dead-code constraints from the unified F062 audit.
@MainActor
final class ScreenCaptureStaticAuditTests: XCTestCase {
    func test_removedIdentityDeadAPIsAndPolicyFieldsStayAbsent() throws {
        let corpus = try productionCorpus()
        for forbidden in [
            "ownerProcessID",
            "screenCaptureShortcutRegistrationDidChange",
            "activatesApplication",
            "ordersMainWindow",
            "initialFocus",
            "func closeAll()",
            "cancelCurrent"
        ] {
            XCTAssertFalse(corpus.contains(forbidden), "Unexpected legacy symbol: \(forbidden)")
        }
    }

    func test_bootstrapAndShutdownKeepExplicitCancellationOwnership() throws {
        let lifecycle = try source(
            "crispyvibes/Features/ScreenCaptureMarkup/Services/LocalScreenCaptureHistoryRepository+Lifecycle.swift"
        )
        XCTAssertTrue(lifecycle.contains("task = Task { [weak self] in"))
        XCTAssertTrue(lifecycle.contains("withTaskCancellationHandler"))
        XCTAssertTrue(lifecycle.contains("task.cancel()"))
        XCTAssertTrue(lifecycle.contains("bootstrapTaskID == taskID"))

        let delivery = try source(
            "crispyvibes/Features/ScreenCaptureMarkup/Services/ScreenCaptureDeliveryCoordinator.swift"
        )
        let shutdown = try XCTUnwrap(delivery.range(of: "func shutdown()"))
        let following = delivery[shutdown.lowerBound...]
        XCTAssertFalse(following.contains("Task {"))
    }

    func test_fileOwnershipAndShortcutAbstractionStayCanonical() throws {
        let services = try source(
            "crispyvibes/Features/ScreenCaptureMarkup/Services/ScreenCaptureServices.swift"
        )
        XCTAssertTrue(services.contains("any GlobalCaptureShortcutManaging"))
        XCTAssertFalse(services.contains("CarbonGlobalCaptureShortcutManager"))

        let composition = try source("crispyvibes/App/AppContainer+ScreenCapture.swift")
        XCTAssertFalse(composition.contains("ScreenCaptureCoordinatorRelay"))
        XCTAssertTrue(composition.contains("commandHandler: { [weak coordinator] command in"))
        XCTAssertTrue(composition.contains("coordinator?.beginCapture()"))
        let carbon = try source(
            "crispyvibes/Features/ScreenCaptureMarkup/Services/CarbonGlobalCaptureShortcutManager.swift"
        )
        XCTAssertTrue(carbon.contains("OptionBits(kEventHotKeyExclusive)"))
        XCTAssertTrue(carbon.contains("Unmanaged.passRetained(CallbackContext(manager: self))"))
        XCTAssertFalse(carbon.contains("Unmanaged.passUnretained(self)"))

        let homeToolbar = try source("crispyvibes/Features/Home/Views/ContentViewToolbar.swift")
        XCTAssertFalse(homeToolbar.contains("struct ScreenCaptureToolbarButton"))
        XCTAssertTrue(homeToolbar.contains("ScreenCaptureToolbarButton(coordinator:"))

        let root = projectRoot
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("crispyvibes/Protocols/ScreenCaptureServices.swift").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                "crispyvibes/Features/ScreenCaptureMarkup/Services/ScreenCaptureServiceGraph.swift"
            ).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                "tests/unit/Features/ScreenCaptureMarkup/ScreenshotStudioTests.swift"
            ).path
        ))
    }

    func test_F062_testCoverageMappingHasEveryUniqueScenarioAndExistingMethods() throws {
        let repositoryRoot = projectRoot.deletingLastPathComponent().deletingLastPathComponent()
        let spec = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "specs/features/platform/screen-capture-markup/spec.md"
            ),
            encoding: .utf8
        )
        let heading = try XCTUnwrap(spec.range(of: "## Test Coverage Mapping"))
        let remainder = spec[heading.upperBound...]
        let sectionEnd = remainder.range(of: "\n## ")?.lowerBound ?? remainder.endIndex
        let section = String(remainder[..<sectionEnd])
        let rows = try captures(
            pattern: #"(?m)^\|\s*(F062-S\d{2})\s*\|([^|]*)\|([^|]*)\|\s*$"#,
            in: section
        )
        let expectedIDs = Set((1...23).map { String(format: "F062-S%02d", $0) })
        let scenarioIDs = try captures(
            pattern: #"(?m)^### Scenario (F062-S\d{2}):"#,
            in: spec
        ).compactMap(\.first)
        XCTAssertEqual(scenarioIDs.count, 23, "Spec must declare exactly 23 F062 scenarios")
        XCTAssertEqual(Set(scenarioIDs).count, 23, "Spec scenario IDs must be unique")
        XCTAssertEqual(Set(scenarioIDs), expectedIDs, "Spec must declare F062-S01 through F062-S23")

        let rowIDs = rows.compactMap(\.first)

        XCTAssertEqual(rows.count, 23, "Mapping must contain exactly 23 scenario rows")
        XCTAssertEqual(Set(rowIDs).count, 23, "Mapping scenario rows must be unique")
        XCTAssertEqual(Set(rowIDs), expectedIDs, "Mapping must cover F062-S01 through F062-S23")

        let testsRoot = projectRoot.appendingPathComponent("tests", isDirectory: true)
        let testCorpus = try FileManager.default.subpathsOfDirectory(atPath: testsRoot.path)
            .filter { $0.hasSuffix(".swift") }
            .map { try String(contentsOf: testsRoot.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        let declarations = Set(
            try captures(pattern: #"\bfunc\s+(test[A-Za-z0-9_]+)\s*\("#, in: testCorpus)
                .compactMap(\.first)
        )
        let methodPattern = #"`(test[A-Za-z0-9_]+)`"#
        var missingMethods: [String] = []
        for row in rows {
            let id = row[0]
            let automatedMethods = try captures(pattern: methodPattern, in: row[1]).compactMap(\.first)
            XCTAssertFalse(
                automatedMethods.isEmpty,
                "\(id) must name at least one automated test method"
            )
            let namedMethods = try captures(
                pattern: methodPattern,
                in: row.dropFirst().joined(separator: " ")
            ).compactMap(\.first)
            missingMethods += namedMethods.filter { !declarations.contains($0) }.map {
                "\(id):\($0)"
            }
        }
        XCTAssertTrue(
            missingMethods.isEmpty,
            "Mapped test methods must exist in current Swift test source: \(missingMethods.joined(separator: ", "))"
        )
    }

    private func captures(pattern: String, in source: String) throws -> [[String]] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: source) else { return nil }
                return String(source[range])
            }
        }
    }

    private var projectRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func productionCorpus() throws -> String {
        let featureRoot = projectRoot.appendingPathComponent(
            "crispyvibes/Features/ScreenCaptureMarkup",
            isDirectory: true
        )
        let files = try FileManager.default.subpathsOfDirectory(atPath: featureRoot.path)
            .filter { $0.hasSuffix(".swift") }
            .map { featureRoot.appendingPathComponent($0) }
        let additional = [
            projectRoot.appendingPathComponent("crispyvibes/App/CrispyVibesApp.swift"),
            projectRoot.appendingPathComponent("crispyvibes/Protocols/ScreenCaptureProtocols.swift")
        ]
        return try (files + additional)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}

extension ScreenCaptureStaticAuditTests {
    func test_copyAndDismissActionAndNormativeIDsStayCanonical() throws {
        let view = try source(
            "crispyvibes/Features/ScreenCaptureMarkup/Views/ScreenshotStudioView.swift"
        )
        XCTAssertTrue(view.contains("AppStrings.ScreenCapture.studioCopyAndDismiss"))
        XCTAssertTrue(view.contains(".keyboardShortcut(.defaultAction)"))
        XCTAssertTrue(view.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(view.contains("screenCapture.studio.copyAndDismiss"))
        XCTAssertTrue(view.contains("AppStrings.ScreenCapture.studioCopy"))
        XCTAssertTrue(view.contains(".buttonStyle(.bordered)"))
        XCTAssertTrue(view.contains(".keyboardShortcut(.cancelAction)"))

        let repositoryRoot = projectRoot.deletingLastPathComponent().deletingLastPathComponent()
        let featureRoot = repositoryRoot.appendingPathComponent(
            "specs/features/platform/screen-capture-markup",
            isDirectory: true
        )
        let spec = try String(
            contentsOf: featureRoot.appendingPathComponent("spec.md"),
            encoding: .utf8
        )
        let threatModel = try String(
            contentsOf: featureRoot.appendingPathComponent("threat-model.md"),
            encoding: .utf8
        )
        let requirementIDs = try captures(
            pattern: #"(?m)^### (F062-R\d{2}):"#,
            in: spec
        ).compactMap(\.first)
        let threatIDs = try captures(
            pattern: #"(?m)^### (F062-T\d{2}):"#,
            in: threatModel
        ).compactMap(\.first)
        XCTAssertEqual(
            requirementIDs,
            (1...20).map { String(format: "F062-R%02d", $0) }
        )
        XCTAssertEqual(
            threatIDs,
            (1...19).map { String(format: "F062-T%02d", $0) }
        )
    }
}
