import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
extension AppShellModelTests {
    func testMarkupEditorThemeTokenBuilderProducesExpectedTokenFamilies() {
        let darkTokens = MarkupEditorThemeTokenBuilder(
            palette: .midnightMono,
            colorScheme: .dark
        )
        .build()
        let lightTokens = MarkupEditorThemeTokenBuilder(
            palette: .sunlitPaper,
            colorScheme: .light
        )
        .build()

        XCTAssertGreaterThanOrEqual(darkTokens.count, 45)
        XCTAssertGreaterThanOrEqual(lightTokens.count, 45)
        XCTAssertNotNil(darkTokens["--focus-outlineColor"])
        XCTAssertNotNil(darkTokens["--fgColor-default"])
        XCTAssertNotNil(darkTokens["--bgColor-default"])
        XCTAssertNotNil(darkTokens["--color-prettylights-syntax-keyword"])
        XCTAssertNotNil(darkTokens["--crispyvibes-editor-border"])
        XCTAssertTrue(darkTokens["--bgColor-neutral-muted"]?.hasPrefix("rgba(") == true)
        XCTAssertTrue(lightTokens["--bgColor-neutral-muted"]?.hasPrefix("rgba(") == true)
    }

    func testEditorFormattingCommandRawValuesAndRequestIdentity() {
        let commands = EditorFormattingCommand.allCases
        XCTAssertEqual(commands.count, 12)
        XCTAssertEqual(EditorFormattingCommand.bold.rawValue, "bold")
        XCTAssertEqual(EditorFormattingCommand.horizontalRule.rawValue, "horizontalRule")

        let requestA = EditorCommandRequest(command: .bold)
        let requestB = EditorCommandRequest(command: .bold)
        XCTAssertEqual(requestA.command, .bold)
        XCTAssertNotEqual(requestA.id, requestB.id)
    }
    func testAppUpdateScheduleAndVersionComparison() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(
            AppUpdateSchedule.shouldRunAutomaticCheck(
                autoCheckEnabled: true,
                lastSuccessfulCheck: nil,
                now: now,
                minimumInterval: 300
            )
        )
        XCTAssertFalse(
            AppUpdateSchedule.shouldRunAutomaticCheck(
                autoCheckEnabled: false,
                lastSuccessfulCheck: nil,
                now: now,
                minimumInterval: 300
            )
        )
        XCTAssertFalse(
            AppUpdateSchedule.shouldRunAutomaticCheck(
                autoCheckEnabled: true,
                lastSuccessfulCheck: now.addingTimeInterval(-120),
                now: now,
                minimumInterval: 300
            )
        )
        XCTAssertTrue(
            AppUpdateSchedule.shouldRunAutomaticCheck(
                autoCheckEnabled: true,
                lastSuccessfulCheck: now.addingTimeInterval(-600),
                now: now,
                minimumInterval: 300
            )
        )

        XCTAssertTrue(
            AppUpdateVersionComparator.isRemoteNewer(
                currentVersion: "0.0",
                currentBuild: "9",
                remoteVersion: "0.0",
                remoteBuild: "10"
            )
        )
        XCTAssertFalse(
            AppUpdateVersionComparator.isRemoteNewer(
                currentVersion: "0.0",
                currentBuild: "10",
                remoteVersion: "0.0",
                remoteBuild: "10"
            )
        )
        XCTAssertTrue(
            AppUpdateVersionComparator.isRemoteNewer(
                currentVersion: "1.17.0",
                currentBuild: "3",
                remoteVersion: "0.0",
                remoteBuild: "99"
            )
        )
    }

    func testAppUpdateManifestDecodingAndDecisionFlow() throws {
        let json = """
        {
          "version": "0.0.20",
          "build": "20",
          "download_url": "https://crispyvibe.com/downloads/CrispyVibes-0.0.20.dmg",
          "release_notes_url": "https://crispyvibe.com/releases/0.0.20",
          "release_notes": "Performance improvements and bug fixes."
        }
        """
        let manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.version, "0.0.20")
        XCTAssertEqual(manifest.build, "20")
        XCTAssertEqual(
            manifest.downloadURL.absoluteString,
            "https://crispyvibe.com/downloads/CrispyVibes-0.0.20.dmg"
        )
        XCTAssertEqual(
            manifest.releaseNotesURL?.absoluteString,
            "https://crispyvibe.com/releases/0.0.20"
        )
        XCTAssertEqual(manifest.releaseNotes, "Performance improvements and bug fixes.")

        switch AppUpdateDecision.evaluate(
            currentVersion: "1.9.0",
            currentBuild: "10",
            manifest: manifest
        ) {
        case let .updateAvailable(candidate):
            XCTAssertEqual(candidate.version, "0.0.20")
        case .upToDate:
            XCTFail("Expected updateAvailable decision for newer manifest.")
        }

        XCTAssertEqual(
            AppUpdateDecision.evaluate(
                currentVersion: "99.0.0",
                currentBuild: "20",
                manifest: manifest
            ),
            .upToDate
        )
    }

    func testAppUpdateManifestRejectsInvalidDownloadURL() {
        let json = """
        {
          "version": "2.0.0",
          "build": "20",
          "download_url": "not-a-valid-url"
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(AppUpdateManifest.self, from: Data(json.utf8))
        )
    }

    func testAppUpdateFeedDefaultsAndInfoPlistMetadata() throws {
        let infoPlist = try loadRepositoryInfoPlist()
        XCTAssertEqual(
            infoPlist[AppPreferences.infoPlistAppUpdateFeedURLKey] as? String,
            "https://crispyvibe.com/updates/macos/dev/appcast.xml"
        )

        XCTAssertEqual(
            AppPreferences.defaultAppUpdateFeedURL,
            "https://crispyvibe.com/updates/macos/dev/appcast.xml"
        )
        XCTAssertEqual(
            AppPreferences.normalizedAppUpdateFeedURL("   "),
            "https://crispyvibe.com/updates/macos/dev/appcast.xml"
        )
        XCTAssertNil(AppPreferences.resolvedAppUpdateFeedURL("invalid url"))

        let suiteName = "app-update-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(AppPreferences.autoUpdateChecksEnabled(userDefaults: defaults))
        defaults.set(false, forKey: AppPreferences.autoUpdateChecksEnabledKey)
        XCTAssertFalse(AppPreferences.autoUpdateChecksEnabled(userDefaults: defaults))
    }

    func testAppUpdateLocalizedMessageFormatting() {
        XCTAssertEqual(
            AppStrings.AppUpdate.upToDateMessage(version: "1.0.6", build: "13"),
            "You're running Crispy 1.0.6 (13). No newer update is available."
        )
        XCTAssertEqual(
            AppStrings.AppUpdate.updateAvailableMessage(
                remoteVersion: "1.0.7",
                remoteBuild: "14",
                currentVersion: "1.0.6",
                currentBuild: "13"
            ),
            "A newer release is available: 1.0.7 (14).\nCurrent version: 1.0.6 (13)."
        )
    }

    func testRasterImagePreviewCenteredInsetsForSmallerImage() {
        let insets = RasterImagePreviewGeometry.centeredInsets(
            viewportSize: CGSize(width: 1000, height: 800),
            imageSize: CGSize(width: 400, height: 200),
            magnification: 1.0
        )

        XCTAssertEqual(insets.left, 300, accuracy: 0.5)
        XCTAssertEqual(insets.right, 300, accuracy: 0.5)
        XCTAssertEqual(insets.top, 300, accuracy: 0.5)
        XCTAssertEqual(insets.bottom, 300, accuracy: 0.5)
    }

    func testRasterImagePreviewCenteredInsetsClampToZeroForOversizedScaledImage() {
        let insets = RasterImagePreviewGeometry.centeredInsets(
            viewportSize: CGSize(width: 1000, height: 800),
            imageSize: CGSize(width: 900, height: 700),
            magnification: 1.5
        )

        XCTAssertEqual(insets.left, 0, accuracy: 0.0001)
        XCTAssertEqual(insets.right, 0, accuracy: 0.0001)
        XCTAssertEqual(insets.top, 0, accuracy: 0.0001)
        XCTAssertEqual(insets.bottom, 0, accuracy: 0.0001)
    }
}
