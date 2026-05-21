import XCTest
@testable import CrispyVibes

@MainActor
final class LayoutPersistencePropertyTests: XCTestCase {
    private var tempRoot: URL!
    private var stateFileURL: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-layout-prop")
        stateFileURL = tempRoot.appendingPathComponent("layout.json")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testPaneLayoutRoundTripIsIdempotentAcrossRandomInputs() {
        let service = LayoutPersistenceService(fileManager: .default, stateFileURL: stateFileURL)

        for iteration in 0..<80 {
            let projectURL = tempRoot.appendingPathComponent("project-\(iteration)", isDirectory: true)
            try? FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

            let candidate = ProjectPaneLayoutState(
                explorerFraction: Double.random(in: -1...2),
                terminalFraction: Double.random(in: -1...2),
                explorerPoints: Bool.random() ? Double.random(in: -100...600) : nil,
                terminalPoints: Bool.random() ? Double.random(in: -100...600) : nil
            )

            service.setPaneLayout(candidate, for: projectURL)
            let expected = candidate.normalized()
            let stored = service.paneLayout(for: projectURL)
            XCTAssertEqual(stored, expected)

            service.setPaneLayout(stored, for: projectURL)
            let storedAgain = service.paneLayout(for: projectURL)
            XCTAssertEqual(storedAgain, expected)
        }
    }
}

@MainActor
final class AppUpdateAndWalkthroughPropertyTests: XCTestCase {
    func testVersionComparatorIsAntisymmetricAcrossRandomizedVersionPairs() {
        for _ in 0..<320 {
            let lhs = randomizedVersionString()
            let rhs = randomizedVersionString()
            let lhsVsRhs = AppUpdateVersionComparator.compare(lhs, rhs)
            let rhsVsLhs = AppUpdateVersionComparator.compare(rhs, lhs)

            switch lhsVsRhs {
            case .orderedAscending:
                XCTAssertEqual(rhsVsLhs, .orderedDescending)
            case .orderedDescending:
                XCTAssertEqual(rhsVsLhs, .orderedAscending)
            case .orderedSame:
                XCTAssertEqual(rhsVsLhs, .orderedSame)
            @unknown default:
                XCTFail("Unhandled comparison result")
            }
        }
    }

    func testAutomaticUpdateScheduleMatchesElapsedTimeProperty() {
        for _ in 0..<260 {
            let autoCheckEnabled = Bool.random()
            let minimumInterval = TimeInterval.random(in: 1...120_000)
            let now = Date(timeIntervalSince1970: TimeInterval.random(in: 10_000...10_000_000))
            let hasLastCheck = Bool.random()
            let elapsed = TimeInterval.random(in: 0...240_000)
            let lastCheck = hasLastCheck ? now.addingTimeInterval(-elapsed) : nil

            let expected: Bool
            if !autoCheckEnabled {
                expected = false
            } else if !hasLastCheck {
                expected = true
            } else {
                expected = elapsed >= minimumInterval
            }

            let result = AppUpdateSchedule.shouldRunAutomaticCheck(
                autoCheckEnabled: autoCheckEnabled,
                lastSuccessfulCheck: lastCheck,
                now: now,
                minimumInterval: minimumInterval
            )
            XCTAssertEqual(result, expected)
        }
    }

    private func randomizedVersionString() -> String {
        let segmentCount = Int.random(in: 1...4)
        let segments = (0..<segmentCount).map { _ in String(Int.random(in: 0...99)) }
        var value = segments.joined(separator: ".")
        if Bool.random() { value = "  \(value)" }
        if Bool.random() { value += "  " }
        return value
    }
}

@MainActor
final class AppUpdateManifestPropertyTests: XCTestCase {
    func testManifestDecodingTrimsWhitespaceAndRespectsAliasesAcrossRandomizedPayloads() throws {
        let downloadKeys = ["downloadURL", "downloadUrl", "download_url"]
        let releaseURLKeys = ["releaseNotesURL", "releaseNotesUrl", "release_notes_url"]
        let releaseNotesKeys = ["releaseNotes", "release_notes"]

        for index in 0..<180 {
            let version = "\(Int.random(in: 0...8)).\(Int.random(in: 0...15)).\(Int.random(in: 0...30))"
            let build = Bool.random() ? "  \(Int.random(in: 0...999))  " : "   "
            let downloadURL = "https://updates.example.com/\(index)/CrispyVibes.dmg"

            let downloadKey = try XCTUnwrap(downloadKeys.randomElement())
            let releaseURLKey = try XCTUnwrap(releaseURLKeys.randomElement())
            let releaseNotesKey = try XCTUnwrap(releaseNotesKeys.randomElement())

            var payload: [String: Any] = [
                "version": "  \(version)  ",
                "build": build,
                downloadKey: "  \(downloadURL)  "
            ]

            let includeReleaseURL = Bool.random()
            let includeReleaseNotes = Bool.random()
            if includeReleaseURL {
                if Bool.random() {
                    payload[releaseURLKey] = "  https://updates.example.com/\(index)/notes  "
                } else {
                    payload[releaseURLKey] = "not-a-url"
                }
            }
            if includeReleaseNotes {
                payload[releaseNotesKey] = "  Notes \(index)  "
            }

            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: data)

            XCTAssertEqual(manifest.version, version)
            XCTAssertEqual(manifest.build, build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : build.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertEqual(manifest.downloadURL.absoluteString, downloadURL)

            if let rawReleaseURL = payload[releaseURLKey] as? String,
               let expected = URL(string: rawReleaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
               expected.scheme != nil {
                XCTAssertEqual(manifest.releaseNotesURL?.absoluteString, expected.absoluteString)
            } else {
                XCTAssertNil(manifest.releaseNotesURL)
            }

            if let rawReleaseNotes = payload[releaseNotesKey] as? String {
                XCTAssertEqual(manifest.releaseNotes, rawReleaseNotes.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                XCTAssertNil(manifest.releaseNotes)
            }
        }
    }

    func testManifestBlankOrMissingBuildDefaultsToZeroAcrossRandomizedPayloads() throws {
        for index in 0..<120 {
            let includeBuild = Bool.random()
            var payload: [String: Any] = [
                "version": "1.\(index).0",
                "download_url": "https://updates.example.com/\(index)/CrispyVibes.dmg"
            ]
            if includeBuild {
                payload["build"] = Bool.random() ? "  " : "\n\t"
            }

            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: data)
            XCTAssertEqual(manifest.build, "0")
        }
    }
}

@MainActor
final class FeatureWalkthroughControllerPropertyTests: XCTestCase {
    func testUITestModePersistsCompletionToSuffixedKeyAcrossRandomizedInputs() throws {
        let truthyValues = ["1", "TRUE", " yes ", "\tON\t"]

        for index in 0..<80 {
            let suiteName = "walkthrough-ui-mode-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let key = "walkthrough.completed.\(index)"
            let uiModeValue = try XCTUnwrap(truthyValues.randomElement())
            let controller = FeatureWalkthroughController(
                defaults: defaults,
                launchEnvironment: [
                    "CRISPYVIBES_UI_TEST_MODE": uiModeValue
                ],
                completedKey: key
            )

            controller.skip()

            XCTAssertFalse(defaults.bool(forKey: key))
            XCTAssertTrue(defaults.bool(forKey: "\(key).ui-test"))
        }
    }

    private func randomizedCasing(_ value: String) -> String {
        String(value.map { character in
            Bool.random() ? Character(String(character).uppercased()) : Character(String(character).lowercased())
        })
    }
}
