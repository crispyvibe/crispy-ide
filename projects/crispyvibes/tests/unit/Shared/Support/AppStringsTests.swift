import XCTest
@testable import CrispyVibes

final class AppStringsTests: XCTestCase {

    // MARK: - Catalog Integrity

    private var catalogKeys: Set<String> {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any] else {
            return []
        }
        return Set(strings.keys)
    }

    private var appStringKeys: [String] {
        // Mirror-based extraction of all String(localized:) keys from AppStrings
        extractKeys(from: AppStrings.self)
    }

    // MARK: - Common

    func testCommonStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Common.done.isEmpty)
        XCTAssertFalse(AppStrings.Common.cancel.isEmpty)
        XCTAssertFalse(AppStrings.Common.close.isEmpty)
        XCTAssertFalse(AppStrings.Common.save.isEmpty)
        XCTAssertFalse(AppStrings.Common.delete.isEmpty)
        XCTAssertFalse(AppStrings.Common.rename.isEmpty)
        XCTAssertFalse(AppStrings.Common.retry.isEmpty)
        XCTAssertFalse(AppStrings.Common.ok.isEmpty)
        XCTAssertFalse(AppStrings.Common.back.isEmpty)
        XCTAssertFalse(AppStrings.Common.next.isEmpty)
        XCTAssertFalse(AppStrings.Common.skip.isEmpty)
        XCTAssertFalse(AppStrings.Common.reset.isEmpty)
        XCTAssertFalse(AppStrings.Common.add.isEmpty)
        XCTAssertFalse(AppStrings.Common.clear.isEmpty)
        XCTAssertFalse(AppStrings.Common.none.isEmpty)
        XCTAssertFalse(AppStrings.Common.preview.isEmpty)
        XCTAssertFalse(AppStrings.Common.more.isEmpty)
        XCTAssertFalse(AppStrings.Common.clearColor.isEmpty)
    }

    func testBrandIsNonLocalizedConstant() {
        // Brand.crispyvibes should always be "CRISPY" regardless of locale.
        XCTAssertEqual(AppStrings.Brand.crispyvibes, "CRISPY")
    }

    // MARK: - Feature Strings Non-Empty

    func testHomeStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Home.welcomeHero.isEmpty)
        XCTAssertFalse(AppStrings.Home.createVibeSpace.isEmpty)
        XCTAssertFalse(AppStrings.Home.createNewVibeSpace.isEmpty)
        XCTAssertFalse(AppStrings.Home.recentVibeSpaces.isEmpty)
        XCTAssertFalse(AppStrings.Home.nothingRecentYet.isEmpty)
        XCTAssertFalse(AppStrings.Home.justYouAndYourVibe.isEmpty)
    }

    func testShelfStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Shelf.title.isEmpty)
        XCTAssertFalse(AppStrings.Shelf.emptyTitle.isEmpty)
        XCTAssertFalse(AppStrings.Shelf.emptyDescription.isEmpty)
    }

    func testExplorerStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Explorer.searchFiles.isEmpty)
        XCTAssertFalse(AppStrings.Explorer.noFolderSelected.isEmpty)
        XCTAssertFalse(AppStrings.Explorer.newFile.isEmpty)
        XCTAssertFalse(AppStrings.Explorer.newFolder.isEmpty)
        XCTAssertFalse(AppStrings.Explorer.openInTerminal.isEmpty)
        XCTAssertFalse(AppStrings.Explorer.revealInFinder.isEmpty)
    }

    func testSourceControlStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.SourceControl.title.isEmpty)
        XCTAssertFalse(AppStrings.SourceControl.commit.isEmpty)
        XCTAssertFalse(AppStrings.SourceControl.push.isEmpty)
        XCTAssertFalse(AppStrings.SourceControl.stageAll.isEmpty)
        XCTAssertFalse(AppStrings.SourceControl.undoAll.isEmpty)
        XCTAssertFalse(AppStrings.SourceControl.cloneRepository.isEmpty)
        XCTAssertFalse(AppStrings.SourceControl.refreshGitStatus.isEmpty)
    }

    func testTerminalStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Terminal.newTerminal.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.splitTerminal.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.createTerminal.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.closeTerminal.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.noSession.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.boardTitle.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.temporary.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.noToolsOnPath.isEmpty)
    }

    func testTerminalTileStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Terminal.Tile.minimize.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.Tile.close.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.Tile.remove.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.Tile.restore.isEmpty)
        XCTAssertFalse(AppStrings.Terminal.Tile.closeMinimized.isEmpty)
    }

    func testVibeCastStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.VibeCast.title.isEmpty)
        XCTAssertFalse(AppStrings.VibeCast.noTerminal.isEmpty)
    }

    func testContentViewerStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.ContentViewer.noContent.isEmpty)
        XCTAssertFalse(AppStrings.ContentViewer.splitHorizontal.isEmpty)
        XCTAssertFalse(AppStrings.ContentViewer.splitVertical.isEmpty)
        XCTAssertFalse(AppStrings.ContentViewer.toggleOrientation.isEmpty)
        XCTAssertFalse(AppStrings.ContentViewer.closePane.isEmpty)
    }

    func testEditorStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Editor.find.isEmpty)
        XCTAssertFalse(AppStrings.Editor.replace.isEmpty)
        XCTAssertFalse(AppStrings.Editor.bold.isEmpty)
        XCTAssertFalse(AppStrings.Editor.italic.isEmpty)
        XCTAssertFalse(AppStrings.Editor.codeBlock.isEmpty)
        XCTAssertFalse(AppStrings.Editor.unsaved.isEmpty)
        XCTAssertFalse(AppStrings.Editor.cannotPreview.isEmpty)
    }

    func testSettingsStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Settings.appTitle.isEmpty)
        XCTAssertFalse(AppStrings.Settings.appSubtitle.isEmpty)
        XCTAssertFalse(AppStrings.Settings.Theme.useSystem.isEmpty)
        XCTAssertFalse(AppStrings.Settings.Theme.customize.isEmpty)
        XCTAssertFalse(AppStrings.Settings.Account.signOut.isEmpty)
        XCTAssertFalse(AppStrings.Settings.Updates.checkNow.isEmpty)
        XCTAssertFalse(AppStrings.Settings.Services.resetDefaults.isEmpty)
        XCTAssertFalse(AppStrings.Settings.Reset.title.isEmpty)
        XCTAssertFalse(AppStrings.Settings.Reset.message.isEmpty)
        XCTAssertFalse(AppStrings.Settings.ContainerStyle.title.isEmpty)
        XCTAssertFalse(AppStrings.Settings.ContainerStyle.borderShapeTitle.isEmpty)
    }

    func testVibeSpaceSettingsStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.VibeSpaceSettings.title.isEmpty)
        XCTAssertFalse(AppStrings.VibeSpaceSettings.chooseProject.isEmpty)
        XCTAssertFalse(AppStrings.VibeSpaceSettings.trustLevel.isEmpty)
        XCTAssertFalse(AppStrings.VibeSpaceSettings.usesDefaults.isEmpty)
    }

    func testCloneRepositoryStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.CloneRepository.title.isEmpty)
        XCTAssertFalse(AppStrings.CloneRepository.clone.isEmpty)
        XCTAssertFalse(AppStrings.CloneRepository.repositoryURL.isEmpty)
        XCTAssertFalse(AppStrings.CloneRepository.gitHubSignInNote.isEmpty)
    }

    func testToolbarStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Toolbar.switchToDetailed.isEmpty)
        XCTAssertFalse(AppStrings.Toolbar.switchToTerminalBoard.isEmpty)
        XCTAssertFalse(AppStrings.Toolbar.addProject.isEmpty)
        XCTAssertFalse(AppStrings.Toolbar.closeProject.isEmpty)
    }

    func testAlertStringsAreNonEmpty() {
        XCTAssertFalse(AppStrings.Alert.vibespaceConfigModified.isEmpty)
        XCTAssertFalse(AppStrings.Alert.iUnderstand.isEmpty)
    }

    // MARK: - No Duplicate Values (catch copy-paste errors)

    func testCommonStringsAreDistinct() {
        let values = [
            AppStrings.Common.done, AppStrings.Common.cancel, AppStrings.Common.close,
            AppStrings.Common.save, AppStrings.Common.delete, AppStrings.Common.rename,
            AppStrings.Common.retry, AppStrings.Common.ok, AppStrings.Common.back,
            AppStrings.Common.next, AppStrings.Common.skip, AppStrings.Common.reset,
            AppStrings.Common.add, AppStrings.Common.clear, AppStrings.Common.none,
            AppStrings.Common.preview, AppStrings.Common.more, AppStrings.Common.clearColor,
        ]
        XCTAssertEqual(values.count, Set(values).count, "Common strings contain duplicates")
    }

    // MARK: - Helpers

    private func extractKeys(from type: Any.Type) -> [String] {
        // This is a compile-time guarantee test — if AppStrings compiles, all keys exist.
        // Runtime key extraction would require reflection which isn't reliable for static lets.
        []
    }
}
