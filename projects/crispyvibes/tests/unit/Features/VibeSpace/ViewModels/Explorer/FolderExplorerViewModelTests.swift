import AppKit
import Foundation
import PDFKit
import SwiftUI
import XCTest
@testable import CrispyVibes

@MainActor
final class FolderExplorerViewModelTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!
    private var viewModel: FolderExplorerViewModel!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-explorer-vm")
        container = AppContainer.makeDefault()
        viewModel = container.makeFolderExplorerViewModel()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        viewModel = nil
        container = nil
    }

    func testSetRootFolderLoadsItemsAndGitState() async throws {
        let docs = tempRoot.appendingPathComponent("Docs", isDirectory: true)
        let readme = tempRoot.appendingPathComponent("README.md")
        let hidden = tempRoot.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data("# Hello\n".utf8).write(to: readme)
        try Data("x".utf8).write(to: hidden)

        viewModel.setRootFolder(tempRoot)
        let loaded = await waitForCondition(timeout: 8) {
            !self.viewModel.rootItems.isEmpty && self.viewModel.workerStatus == .ready && self.viewModel.gitState != .loading
        }
        XCTAssertTrue(loaded)

        XCTAssertEqual(viewModel.rootURL?.path, tempRoot.standardizedFileURL.path)
        XCTAssertEqual(viewModel.selectedFolderURL?.path, tempRoot.standardizedFileURL.path)
        XCTAssertEqual(viewModel.activeSidebarTab, .files)

        let names = viewModel.rootItems.map(\.displayName)
        XCTAssertTrue(names.contains("Docs"))
        XCTAssertTrue(names.contains("README.md"))
        XCTAssertTrue(names.contains(".hidden"))
    }

    func testToggleExpansionLoadsChildrenAndSearchMatchesNestedItems() async throws {
        let sources = tempRoot.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("print(\"ok\")\n".utf8).write(to: sources.appendingPathComponent("main.swift"))

        viewModel.setRootFolder(tempRoot)
        let initialLoad = await waitForCondition(timeout: 8) { !self.viewModel.rootItems.isEmpty }
        XCTAssertTrue(initialLoad)
        guard let directory = viewModel.rootItems.first(where: { $0.isDirectory }) else {
            return XCTFail("Expected directory item.")
        }

        viewModel.toggleExpansion(for: directory)
        XCTAssertTrue(viewModel.expandedDirectoryIDs.contains(directory.id))

        let childrenLoaded = await waitForCondition(timeout: 8) {
            guard let refreshed = self.viewModel.rootItems.first(where: { $0.id == directory.id }) else { return false }
            return refreshed.children?.contains(where: { $0.displayName == "main.swift" }) == true
        }
        XCTAssertTrue(childrenLoaded)

        viewModel.searchQuery = "main.swift"
        let filteredMatches = await waitForCondition(timeout: 2) {
            self.viewModel.displayedItems.count == 1
                && self.viewModel.displayedItems.first?.displayName == "Sources"
                && self.viewModel.displayedItems.first?.children?.first?.displayName == "main.swift"
        }
        XCTAssertTrue(filteredMatches)

        viewModel.searchQuery = "missing-token"
        let noMatches = await waitForCondition(timeout: 2) { self.viewModel.displayedItems.isEmpty }
        XCTAssertTrue(noMatches)

        viewModel.searchQuery = ""
        let resetToUnfiltered = await waitForCondition(timeout: 2) { !self.viewModel.displayedItems.isEmpty }
        XCTAssertTrue(resetToUnfiltered)

        viewModel.toggleExpansion(for: directory)
        XCTAssertFalse(viewModel.expandedDirectoryIDs.contains(directory.id))
    }

    func testToggleExpansionDoesNothingWhileSearchIsActive() async throws {
        let sources = tempRoot.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("print(\"ok\")\n".utf8).write(to: sources.appendingPathComponent("main.swift"))

        viewModel.setRootFolder(tempRoot)
        let initialLoad = await waitForCondition(timeout: 8) { !self.viewModel.rootItems.isEmpty }
        XCTAssertTrue(initialLoad)

        guard let directory = viewModel.rootItems.first(where: { $0.displayName == "Sources" }) else {
            return XCTFail("Expected Sources directory item.")
        }

        viewModel.toggleExpansion(for: directory)
        let childrenLoaded = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems.first(where: { $0.id == directory.id })?.children?.isEmpty == false
        }
        XCTAssertTrue(childrenLoaded)
        XCTAssertTrue(viewModel.expandedDirectoryIDs.contains(directory.id))

        viewModel.searchQuery = "main.swift"
        let filteredMatches = await waitForCondition(timeout: 2) {
            self.viewModel.displayedItems.first?.children?.first?.displayName == "main.swift"
        }
        XCTAssertTrue(filteredMatches)

        viewModel.toggleExpansion(for: directory)
        XCTAssertTrue(viewModel.expandedDirectoryIDs.contains(directory.id))
    }

    func testCollapsingParentDirectoryClearsExpandedDescendants() {
        let nestedFile = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/Feature/main.swift"), isDirectory: false)
        let nestedDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Feature"),
            isDirectory: true,
            children: [nestedFile]
        )
        let parentDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [nestedDirectory]
        )

        viewModel.replaceRootItems([parentDirectory])
        viewModel.expandedDirectoryIDs = [parentDirectory.id, nestedDirectory.id]

        viewModel.toggleExpansion(for: parentDirectory)

        XCTAssertFalse(viewModel.expandedDirectoryIDs.contains(parentDirectory.id))
        XCTAssertFalse(viewModel.expandedDirectoryIDs.contains(nestedDirectory.id))
    }

    func testCollapsingDirectoryWithStaleItemClearsExpandedDescendantsByPath() {
        let staleParentDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true
        )
        let nestedDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Feature"),
            isDirectory: true
        )
        let deeperDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Feature/Nested"),
            isDirectory: true
        )

        viewModel.expandedDirectoryIDs = [
            staleParentDirectory.id,
            nestedDirectory.id,
            deeperDirectory.id
        ]

        viewModel.toggleExpansion(for: staleParentDirectory)

        XCTAssertFalse(viewModel.expandedDirectoryIDs.contains(staleParentDirectory.id))
        XCTAssertFalse(viewModel.expandedDirectoryIDs.contains(nestedDirectory.id))
        XCTAssertFalse(viewModel.expandedDirectoryIDs.contains(deeperDirectory.id))
    }

    func testSearchFilteringIsDebounced() async throws {
        try Data("print(\"ok\")\n".utf8).write(to: tempRoot.appendingPathComponent("main.swift"))
        try Data("note\n".utf8).write(to: tempRoot.appendingPathComponent("notes.txt"))

        viewModel.setRootFolder(tempRoot)
        let initialLoad = await waitForCondition(timeout: 8) { !self.viewModel.rootItems.isEmpty }
        XCTAssertTrue(initialLoad)
        let initialCount = viewModel.displayedItems.count

        viewModel.searchQuery = "main.swift"
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(viewModel.displayedItems.count, initialCount)

        let filteredMatches = await waitForCondition(timeout: 2) {
            self.viewModel.displayedItems.count == 1
                && self.viewModel.displayedItems.first?.displayName == "main.swift"
        }
        XCTAssertTrue(filteredMatches)
    }

    func testConsumeExternalRefreshQueueReloadsExpandedDirectoryWhenRootAndChildEventsArriveTogether() async throws {
        let sources = tempRoot.appendingPathComponent("Sources", isDirectory: true)
        let initialFile = sources.appendingPathComponent("main.swift")
        let newFile = sources.appendingPathComponent("new.swift")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("print(\"ok\")\n".utf8).write(to: initialFile)

        viewModel.setRootFolder(tempRoot)
        let initialLoad = await waitForCondition(timeout: 8) { !self.viewModel.rootItems.isEmpty }
        XCTAssertTrue(initialLoad)

        guard let directory = viewModel.rootItems.first(where: { $0.displayName == "Sources" }) else {
            return XCTFail("Expected Sources directory item.")
        }

        viewModel.toggleExpansion(for: directory)
        let childrenLoaded = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems.first(where: { $0.id == directory.id })?.children?.contains(where: { $0.displayName == "main.swift" }) == true
        }
        XCTAssertTrue(childrenLoaded)

        try Data("print(\"new\")\n".utf8).write(to: newFile)
        viewModel.pendingExternalRefreshPaths = [tempRoot.standardizedFileURL.path, sources.standardizedFileURL.path]
        viewModel.consumeExternalRefreshQueue()

        let refreshed = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems.first(where: { $0.id == directory.id })?.children?.contains(where: { $0.displayName == "new.swift" }) == true
        }
        XCTAssertTrue(refreshed)
    }

    func testWatcherRefreshTargetsContentFileChangeToContainingExpandedDirectory() async throws {
        let sources = tempRoot.appendingPathComponent("Sources", isDirectory: true)
        let fileURL = sources.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("print(\"ok\")\n".utf8).write(to: fileURL)

        viewModel.setRootFolder(tempRoot)
        let initialLoad = await waitForCondition(timeout: 8) { !self.viewModel.rootItems.isEmpty }
        XCTAssertTrue(initialLoad)

        guard let directory = viewModel.rootItems.first(where: { $0.displayName == "Sources" }) else {
            return XCTFail("Expected Sources directory item.")
        }

        viewModel.toggleExpansion(for: directory)
        let childrenLoaded = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems.first(where: { $0.id == directory.id })?.children?.isEmpty == false
        }
        XCTAssertTrue(childrenLoaded)

        let event = DirectoryWatcher.Event(
            path: fileURL.standardizedFileURL.path,
            kind: .modified,
            isDirectory: false,
            rawFlags: 0
        )
        let targets = viewModel.watcherRefreshTargetDirectoryPaths(
            for: [fileURL.standardizedFileURL.path],
            changedEvents: [fileURL.standardizedFileURL.path: event],
            rootPath: tempRoot.standardizedFileURL.path
        )

        XCTAssertEqual(targets, [sources.standardizedFileURL.path])
    }

    func testConsumeExternalRefreshQueueDoesNotShowLoadingRowForContentOnlyFileEdit() async throws {
        let sources = tempRoot.appendingPathComponent("Sources", isDirectory: true)
        let fileURL = sources.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("print(\"ok\")\n".utf8).write(to: fileURL)

        viewModel.setRootFolder(tempRoot)
        let initialLoad = await waitForCondition(timeout: 8) { !self.viewModel.rootItems.isEmpty }
        XCTAssertTrue(initialLoad)

        guard let directory = viewModel.rootItems.first(where: { $0.displayName == "Sources" }) else {
            return XCTFail("Expected Sources directory item.")
        }

        viewModel.toggleExpansion(for: directory)
        let childrenLoaded = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems.first(where: { $0.id == directory.id })?.children?.contains(where: { $0.displayName == "main.swift" }) == true
        }
        XCTAssertTrue(childrenLoaded)
        XCTAssertTrue(viewModel.loadingDirectoryIDs.isEmpty)

        try Data("print(\"updated\")\n".utf8).write(to: fileURL)
        viewModel.pendingExternalRefreshPaths = [fileURL.standardizedFileURL.path]
        viewModel.pendingExternalRefreshEvents = [
            fileURL.standardizedFileURL.path: DirectoryWatcher.Event(
                path: fileURL.standardizedFileURL.path,
                kind: .modified,
                isDirectory: false,
                rawFlags: 0
            )
        ]

        viewModel.consumeExternalRefreshQueue()

        XCTAssertTrue(viewModel.loadingDirectoryIDs.isEmpty)

        let refreshSettled = await waitForCondition(timeout: 8) {
            self.viewModel.loadingDirectoryIDs.isEmpty
                && self.viewModel.rootItems
                    .first(where: { $0.id == directory.id })?
                    .children?
                    .contains(where: { $0.displayName == "main.swift" }) == true
        }
        XCTAssertTrue(refreshSettled)
        XCTAssertTrue(viewModel.loadingDirectoryIDs.isEmpty)
    }

    func testCreateRenameDeleteWorkflowAndSelectionMapping() async throws {
        viewModel.setRootFolder(tempRoot)
        let ready = await waitForCondition(timeout: 8) { self.viewModel.workerStatus == .ready }
        XCTAssertTrue(ready)

        viewModel.createNewFile(in: nil)
        let created = await waitForCondition(timeout: 8) {
            self.viewModel.renamingItemID != nil && self.viewModel.selectedFileURL != nil
        }
        XCTAssertTrue(created)

        guard let createdFileURL = viewModel.selectedFileURL else {
            return XCTFail("Expected selected file URL after creation.")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdFileURL.path))

        viewModel.renameText = "renamed.md"
        viewModel.commitRename()
        let renamedURL = tempRoot.appendingPathComponent("renamed.md")
        let renamed = await waitForCondition(timeout: 8) { FileManager.default.fileExists(atPath: renamedURL.path) }
        XCTAssertTrue(renamed)

        let appearsInList = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems.contains(where: { $0.displayName == "renamed.md" })
        }
        XCTAssertTrue(appearsInList)

        guard let renamedItem = viewModel.rootItems.first(where: { $0.displayName == "renamed.md" }) else {
            return XCTFail("Expected renamed item in root items.")
        }
        viewModel.select(renamedItem)
        XCTAssertEqual(
            viewModel.selectedFileURL?.standardizedFileURL.path,
            renamedURL.standardizedFileURL.path
        )

        viewModel.deleteItem(renamedItem)
        let deleted = await waitForCondition(timeout: 8) {
            !FileManager.default.fileExists(atPath: renamedURL.path) && self.viewModel.selectedFileURL == nil
        }
        XCTAssertTrue(deleted)

        viewModel.createNewFolder(in: nil)
        let folderCreated = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems.contains(where: { $0.isDirectory && $0.displayName.hasPrefix("New Folder") })
        }
        XCTAssertTrue(folderCreated)
    }

    func testMoveItemBetweenDirectoriesUpdatesTreeAndSelection() async throws {
        let sourceFolder = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let destinationFolder = tempRoot.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let movingFile = sourceFolder.appendingPathComponent("move-me.txt")
        try Data("content".utf8).write(to: movingFile)

        viewModel.setRootFolder(tempRoot)
        let ready = await waitForCondition(timeout: 8) { self.viewModel.workerStatus == .ready }
        XCTAssertTrue(ready)

        guard let sourceFolderItem = viewModel.rootItems.first(where: { $0.displayName == "Source" }) else {
            return XCTFail("Expected Source directory in explorer tree.")
        }
        viewModel.toggleExpansion(for: sourceFolderItem)
        let childLoaded = await waitForCondition(timeout: 8) {
            self.viewModel.rootItems
                .first(where: { $0.id == sourceFolderItem.id })?
                .children?
                .contains(where: { $0.displayName == "move-me.txt" }) == true
        }
        XCTAssertTrue(childLoaded)

        guard
            let refreshedSource = viewModel.rootItems.first(where: { $0.id == sourceFolderItem.id }),
            let movingItem = refreshedSource.children?.first(where: { $0.displayName == "move-me.txt" })
        else {
            return XCTFail("Expected move-me.txt in Source directory.")
        }
        viewModel.select(movingItem)

        viewModel.moveItem(at: movingFile.path, toDirectory: destinationFolder.path)
        let moved = await waitForCondition(timeout: 8) {
            FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent("move-me.txt").path)
        }
        XCTAssertTrue(moved)
    }

    func testCopyItemBetweenDirectoriesKeepsSourceFileAndRefreshesTree() async throws {
        let sourceFolder = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let destinationFolder = tempRoot.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy-me.txt")
        try Data("content".utf8).write(to: sourceFile)

        viewModel.setRootFolder(tempRoot)
        let ready = await waitForCondition(timeout: 8) { self.viewModel.workerStatus == .ready }
        XCTAssertTrue(ready)

        viewModel.copyItem(at: sourceFile.path, toDirectory: destinationFolder.path)
        let copied = await waitForCondition(timeout: 8) {
            FileManager.default.fileExists(atPath: sourceFile.path) &&
            FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent("copy-me.txt").path)
        }
        XCTAssertTrue(copied)
    }

    func testExplorerOpenRequestDifferentiatesPreviewAndOpenTab() async throws {
        let fileURL = tempRoot.appendingPathComponent("README.md")
        try Data("# Readme\n".utf8).write(to: fileURL)

        viewModel.setRootFolder(tempRoot)
        let loaded = await waitForCondition(timeout: 8) { !self.viewModel.rootItems.isEmpty }
        XCTAssertTrue(loaded)
        guard let item = viewModel.rootItems.first(where: { $0.displayName == "README.md" }) else {
            return XCTFail("Expected README.md in tree")
        }

        viewModel.select(item)
        XCTAssertEqual(viewModel.openRequest?.action, .preview)
        XCTAssertEqual(viewModel.openRequest?.fileURL.standardizedFileURL.path, fileURL.standardizedFileURL.path)

        viewModel.openInTab(item)
        XCTAssertEqual(viewModel.openRequest?.action, .openTab)
        XCTAssertEqual(viewModel.openRequest?.fileURL.standardizedFileURL.path, fileURL.standardizedFileURL.path)

        viewModel.openInWindow(item)
        XCTAssertEqual(viewModel.openRequest?.action, .openWindow)
        XCTAssertEqual(viewModel.openRequest?.fileURL.standardizedFileURL.path, fileURL.standardizedFileURL.path)
    }

    func testSelectGitStatusItemHandlesMissingAndExistingFiles() throws {
        let existingFile = tempRoot.appendingPathComponent("exists.txt")
        try Data("ok".utf8).write(to: existingFile)

        let missing = GitStatusItem(
            code: "M ",
            indexStatus: "M",
            workTreeStatus: " ",
            relativePath: "missing.txt",
            url: tempRoot.appendingPathComponent("missing.txt")
        )
        viewModel.selectGitStatusItem(missing)
        XCTAssertTrue((viewModel.userFacingError ?? "").contains("File does not exist"))

        viewModel.clearError()
        XCTAssertNil(viewModel.userFacingError)

        let existing = GitStatusItem(
            code: "M ",
            indexStatus: "M",
            workTreeStatus: " ",
            relativePath: "exists.txt",
            url: existingFile
        )
        viewModel.selectGitStatusItem(existing)
        XCTAssertEqual(viewModel.selectedFileURL?.path, existingFile.path)
        XCTAssertEqual(viewModel.selectedItemID, existingFile.path)

        let deleted = GitStatusItem(
            code: " D",
            indexStatus: " ",
            workTreeStatus: "D",
            relativePath: "removed.txt",
            url: tempRoot.appendingPathComponent("removed.txt")
        )
        viewModel.selectGitStatusItem(deleted)
        XCTAssertNil(viewModel.userFacingError)
        XCTAssertEqual(viewModel.openRequest?.action, .compareGitStatus(code: " D", relativePath: "removed.txt"))
    }

    func testRefreshTreeFailureAndCreateWithoutRootSurfaceErrors() async {
        let missingRoot = tempRoot.appendingPathComponent("missing-root", isDirectory: true)
        viewModel.setRootFolder(missingRoot)
        let failedLoad = await waitForCondition(timeout: 8) { self.viewModel.workerStatus.level == .unavailable }
        XCTAssertTrue(failedLoad)
        XCTAssertTrue((viewModel.userFacingError ?? "").contains("Failed to read"))

        let noRootViewModel = container.makeFolderExplorerViewModel()
        noRootViewModel.createNewFile(in: nil)
        XCTAssertEqual(noRootViewModel.userFacingError, "Select a folder first.")
    }

    func testSetRootFolderIncludesDotFoldersAndMarksGitIgnoredEntries() async throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let dotFolder = tempRoot.appendingPathComponent(".vscode", isDirectory: true)
        let ignoredFolder = tempRoot.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: dotFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredFolder, withIntermediateDirectories: true)
        try Data("build/\n".utf8).write(to: tempRoot.appendingPathComponent(".gitignore"))

        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: tempRoot)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "core.excludesfile", "/dev/null"], workingDirectory: tempRoot)

        viewModel.setRootFolder(tempRoot)
        let loaded = await waitForCondition(timeout: 8) {
            !self.viewModel.rootItems.isEmpty && self.viewModel.workerStatus == .ready
        }
        XCTAssertTrue(loaded)

        let dotEntry = try XCTUnwrap(viewModel.rootItems.first(where: { $0.displayName == ".vscode" }))
        XCTAssertTrue(dotEntry.isDirectory)
        XCTAssertFalse(dotEntry.isGitIgnored)

        let ignoredEntry = try XCTUnwrap(viewModel.rootItems.first(where: { $0.displayName == "build" }))
        XCTAssertTrue(ignoredEntry.isGitIgnored)
    }

    func testGitStatusItemPropertyFlagsRemainConsistent() {
        let states = [" ", "M", "A", "D", "R", "?", "U"]
        let iterations = 160

        for iteration in 0..<iterations {
            let indexStatus = states[iteration % states.count]
            let workTreeStatus = states[(iteration * 7 + 3) % states.count]
            let code = "\(indexStatus)\(workTreeStatus)"
            let item = GitStatusItem(
                code: code,
                indexStatus: indexStatus,
                workTreeStatus: workTreeStatus,
                relativePath: "f-\(iteration).txt",
                url: tempRoot.appendingPathComponent("f-\(iteration).txt")
            )

            XCTAssertFalse(item.canUnstage && !item.isStaged)
            XCTAssertFalse(item.canStage && !item.hasUnstagedChanges && !item.isUntracked)
            if item.isUntracked {
                XCTAssertFalse(item.isStaged)
            }
        }
    }

    func testDirectoryWatcherCappedNormalizedPathsPrioritizesShallowDirectories() {
        let input: Set<String> = [
            "/tmp/root",
            "/tmp/root/a",
            "/tmp/root/c",
            "/tmp/root/a/b",
            "/tmp/root/c/d"
        ]

        let capped = DirectoryWatcher.cappedNormalizedPaths(from: input, maxWatchedPaths: 3)

        XCTAssertEqual(capped.count, 3)
        XCTAssertTrue(capped.contains("/tmp/root"))
        XCTAssertTrue(capped.contains("/tmp/root/a"))
        XCTAssertTrue(capped.contains("/tmp/root/c"))
    }

    func testDirectoryWatcherCappedNormalizedPathsReturnsNormalizedSetWhenUnderLimit() {
        let input: Set<String> = [
            "/tmp/vibespace/./project",
            "/tmp/vibespace/project/../project/src"
        ]

        let capped = DirectoryWatcher.cappedNormalizedPaths(from: input, maxWatchedPaths: 8)

        XCTAssertEqual(
            capped,
            Set([
                "/tmp/vibespace/project",
                "/tmp/vibespace/project/src"
            ])
        )
    }

    func testDirectoryWatcherReportsNestedFileChangesUnderWatchedRoot() throws {
        let nestedDirectoryURL = tempRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let fileURL = nestedDirectoryURL.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)

        let expectation = expectation(description: "Directory watcher reports nested file change")
        let watcher = DirectoryWatcher()
        watcher.setOnChange { changedPath in
            if changedPath == fileURL.standardizedFileURL.path {
                expectation.fulfill()
            }
        }
        watcher.updateWatchedPaths([tempRoot.path])

        try Data("print(\"hello\")\n".utf8).write(to: fileURL, options: .atomic)

        wait(for: [expectation], timeout: 5.0)
        watcher.invalidate()
    }
}

@MainActor
final class AppKitTreeViewCoordinatorTests: XCTestCase {
    func testDirectoryPrimaryClickSelectsAndTogglesExpansion() {
        let leaf = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/Feature/main.swift"), isDirectory: false)
        let nestedDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Feature"),
            isDirectory: true,
            children: [leaf]
        )
        let rootDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [nestedDirectory]
        )

        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [rootDirectory],
            expandedIDs: [rootDirectory.id, nestedDirectory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let (coordinator, _, outlineView, window) = makeMountedOutline(for: treeView)
        let rootNode = coordinator.node(for: rootDirectory)
        let nestedNode = coordinator.node(for: nestedDirectory)
        let nestedRow = outlineView.row(forItem: nestedNode)
        XCTAssertGreaterThanOrEqual(nestedRow, 0)
        XCTAssertTrue(outlineView.isItemExpanded(rootNode))
        XCTAssertTrue(outlineView.isItemExpanded(nestedNode))

        let event = mouseEvent(forRow: nestedRow, in: outlineView)
        XCTAssertEqual(outlineView.row(at: outlineView.convert(event.locationInWindow, from: nil)), nestedRow)

        withExtendedLifetime(window) {
            XCTAssertTrue(coordinator.handlePrimaryClick(on: nestedNode, event: event))
        }

        XCTAssertTrue(coordinator.expandedIDs.contains(rootDirectory.id))
        XCTAssertFalse(coordinator.expandedIDs.contains(nestedDirectory.id))
        XCTAssertEqual(actions.count, 2)
        assertSelectThenToggleActionSequence(actions, expectedItem: nestedDirectory)
    }

    func testDirectorySelectionPathSelectsWithoutCollapsingIt() {
        let looseFile = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/README.md"), isDirectory: false)
        let nestedLeaf = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/Feature/main.swift"), isDirectory: false)
        let nestedDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Feature"),
            isDirectory: true,
            children: [nestedLeaf]
        )
        let siblingDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Utilities"),
            isDirectory: true
        )
        let rootDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [looseFile, nestedDirectory, siblingDirectory]
        )

        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [rootDirectory],
            expandedIDs: [rootDirectory.id, nestedDirectory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let (coordinator, _, outlineView, _) = makeMountedOutline(for: treeView)
        let rootNode = coordinator.node(for: rootDirectory)
        let nestedNode = coordinator.node(for: nestedDirectory)
        let siblingNode = coordinator.node(for: siblingDirectory)

        XCTAssertTrue(outlineView.isItemExpanded(rootNode))
        XCTAssertTrue(outlineView.isItemExpanded(nestedNode))
        XCTAssertGreaterThanOrEqual(outlineView.row(forItem: siblingNode), 0)

        XCTAssertTrue(coordinator.outlineView(outlineView, shouldSelectItem: nestedNode))

        XCTAssertTrue(coordinator.expandedIDs.contains(rootDirectory.id))
        XCTAssertTrue(coordinator.expandedIDs.contains(nestedDirectory.id))
        XCTAssertTrue(outlineView.isItemExpanded(rootNode))
        XCTAssertTrue(outlineView.isItemExpanded(nestedNode))
        XCTAssertGreaterThanOrEqual(outlineView.row(forItem: siblingNode), 0)
        XCTAssertEqual(actions.count, 1)
        guard case .select(let selectedItem)? = actions.first else {
            return XCTFail("Expected select action, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(selectedItem, nestedDirectory)
    }

    func testMountedOutlineDoubleClickOpensFileInTab() {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/main.swift"), isDirectory: false)
        let rootDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [file]
        )

        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [rootDirectory],
            expandedIDs: [rootDirectory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let (coordinator, _, outlineView, window) = makeMountedOutline(for: treeView)
        let fileNode = coordinator.node(for: file)
        let fileRow = outlineView.row(forItem: fileNode)
        XCTAssertGreaterThanOrEqual(fileRow, 0)

        let event = mouseEvent(forRow: fileRow, in: outlineView, clickCount: 2)
        withExtendedLifetime(window) {
            outlineView.mouseDown(with: event)
        }

        XCTAssertEqual(actions.count, 2)
        guard case .select(let selectedItem)? = actions.first else {
            return XCTFail("Expected select action first, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(selectedItem, file)
        guard case .openInTab(let openedItem) = actions[1] else {
            return XCTFail("Expected openInTab action second, got \(actions[1]).")
        }
        XCTAssertEqual(openedItem, file)
    }

    func testMountedOutlineSingleClickFileUsesOutlineSelectionHandling() {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/main.swift"), isDirectory: false)
        let rootDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [file]
        )

        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [rootDirectory],
            expandedIDs: [rootDirectory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let (coordinator, _, outlineView, window) = makeMountedOutline(for: treeView)
        let fileNode = coordinator.node(for: file)
        let fileRow = outlineView.row(forItem: fileNode)
        XCTAssertGreaterThanOrEqual(fileRow, 0)

        let event = mouseEvent(forRow: fileRow, in: outlineView)
        XCTAssertFalse(coordinator.handlePrimaryClick(on: fileNode, event: event))

        withExtendedLifetime(window) {
            XCTAssertTrue(coordinator.outlineView(outlineView, shouldSelectItem: fileNode))
            coordinator.isSyncingSelection = true
            defer { coordinator.isSyncingSelection = false }
            outlineView.selectRowIndexes(IndexSet(integer: fileRow), byExtendingSelection: false)
        }

        XCTAssertEqual(actions.count, 1)
        guard case .select(let selectedItem)? = actions.first else {
            return XCTFail("Expected select action, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(selectedItem, file)
        XCTAssertEqual(outlineView.selectedRow, fileRow)
    }

    func testRootBackgroundContextMenuProvidesCreationActions() throws {
        let rootDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true
        )
        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [rootDirectory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            rootURL: rootDirectory.url,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let (_, _, outlineView, window) = makeMountedOutline(for: treeView)
        let event = rightMouseEvent(
            at: NSPoint(x: 40, y: outlineView.bounds.height - 8),
            in: outlineView
        )

        let menu = try XCTUnwrap(withExtendedLifetime(window) {
            outlineView.menu(for: event)
        })

        XCTAssertEqual(menu.itemTitlesExcludingSeparators, ["New File", "New Folder"])
        XCTAssertEqual(outlineView.selectedRow, -1)
        XCTAssertTrue(actions.isEmpty)
    }

    func testDisclosureButtonCollapseDoesNotReopenDirectoryFromStaleParentState() throws {
        let leaf = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/Feature/main.swift"), isDirectory: false)
        let nestedDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Feature"),
            isDirectory: true,
            children: [leaf]
        )
        let rootDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [nestedDirectory]
        )

        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [rootDirectory],
            expandedIDs: [rootDirectory.id, nestedDirectory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let (coordinator, _, outlineView, window) = makeMountedOutline(for: treeView)
        let nestedNode = coordinator.node(for: nestedDirectory)
        let disclosureButton = try XCTUnwrap(disclosureButton(forRow: outlineView.row(forItem: nestedNode), in: outlineView))

        withExtendedLifetime(window) {
            disclosureButton.performClick(nil)
        }

        XCTAssertFalse(outlineView.isItemExpanded(nestedNode))

        coordinator.expandedIDs = [rootDirectory.id, nestedDirectory.id]
        coordinator.reconcilePendingExpansionStates()
        coordinator.syncExpansionState()

        XCTAssertTrue(coordinator.expandedIDs.contains(rootDirectory.id))
        XCTAssertFalse(coordinator.expandedIDs.contains(nestedDirectory.id))
        XCTAssertFalse(outlineView.isItemExpanded(nestedNode))
        XCTAssertEqual(actions.count, 1)
        assertSingleToggleExpansionAction(actions, expectedItem: nestedDirectory)
    }

    func testNonScrollingTreeUsesIntrinsicHeightFromVisibleRows() {
        let leaf = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/main.swift"), isDirectory: false)
        let directory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [leaf]
        )
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: false,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { _ in },
            onTransferDrop: { _ in false }
        )

        let (coordinator, scrollView, _, _) = makeMountedOutline(for: treeView)
        let collapsedHeight = scrollView.intrinsicContentSize.height

        coordinator.expandedIDs.insert(directory.id)
        coordinator.syncExpansionState()
        scrollView.invalidateIntrinsicContentSize()

        let expandedHeight = scrollView.intrinsicContentSize.height
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)
    }

    func testIntrinsicSizeInvalidationSkipsRenameUpdatesForNonScrollingTree() {
        XCTAssertFalse(
            AppKitTreeView.shouldInvalidateIntrinsicContentSize(
                allowsScrolling: false,
                previousRowCount: 8,
                currentRowCount: 8,
                renamingID: "/tmp/project/main.swift"
            )
        )
    }

    func testIntrinsicSizeInvalidationTracksRowCountChangesWhenNotRenaming() {
        XCTAssertTrue(
            AppKitTreeView.shouldInvalidateIntrinsicContentSize(
                allowsScrolling: false,
                previousRowCount: 4,
                currentRowCount: 7,
                renamingID: nil
            )
        )
        XCTAssertFalse(
            AppKitTreeView.shouldInvalidateIntrinsicContentSize(
                allowsScrolling: true,
                previousRowCount: 4,
                currentRowCount: 7,
                renamingID: nil
            )
        )
    }

    func testDirectoryClickAndCollapseNotificationEmitSingleCollapseAction() {
        let directory = makeDirectoryItem(path: "/tmp/project/Sources")
        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [directory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        let outlineView = NSOutlineView()
        let node = coordinator.node(for: directory)

        XCTAssertTrue(coordinator.outlineView(outlineView, shouldSelectItem: node))
        guard case .select(let selectedItem)? = actions.first else {
            return XCTFail("Expected select action, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(selectedItem, directory)
        actions.removeAll()

        coordinator.outlineViewItemDidCollapse(
            Notification(
                name: NSOutlineView.itemDidCollapseNotification,
                object: outlineView,
                userInfo: ["NSObject": node]
            )
        )

        XCTAssertEqual(actions.count, 1)
        assertSingleToggleExpansionAction(actions, expectedItem: directory)
    }

    func testDirectoryClickAndExpandNotificationEmitSingleExpandAction() {
        let directory = makeDirectoryItem(path: "/tmp/project/Sources")
        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        let outlineView = NSOutlineView()
        let node = coordinator.node(for: directory)

        XCTAssertTrue(coordinator.outlineView(outlineView, shouldSelectItem: node))
        guard case .select(let selectedItem)? = actions.first else {
            return XCTFail("Expected select action, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(selectedItem, directory)
        actions.removeAll()

        coordinator.outlineViewItemDidExpand(
            Notification(
                name: NSOutlineView.itemDidExpandNotification,
                object: outlineView,
                userInfo: ["NSObject": node]
            )
        )

        XCTAssertEqual(actions.count, 1)
        assertSingleToggleExpansionAction(actions, expectedItem: directory)
    }

    func testNativeCollapseNotificationWithoutSelectionStillEmitsActionOnce() {
        let directory = makeDirectoryItem(path: "/tmp/project/Sources")
        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [directory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        let outlineView = NSOutlineView()
        let node = coordinator.node(for: directory)

        coordinator.outlineViewItemDidCollapse(
            Notification(
                name: NSOutlineView.itemDidCollapseNotification,
                object: outlineView,
                userInfo: ["NSObject": node]
            )
        )
        coordinator.outlineViewItemDidCollapse(
            Notification(
                name: NSOutlineView.itemDidCollapseNotification,
                object: outlineView,
                userInfo: ["NSObject": node]
            )
        )

        XCTAssertEqual(actions.count, 1)
        assertSingleToggleExpansionAction(actions, expectedItem: directory)
    }

    func testSearchQueryTreatsVisibleDirectoriesAsExpandedAndSelectsInsteadOfToggling() {
        let child = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/main.swift"), isDirectory: false)
        let directory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [child]
        )
        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "main.swift",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        let outlineView = NSOutlineView()
        let node = coordinator.node(for: directory)

        XCTAssertTrue(coordinator.isEffectivelyExpanded(directory.id))
        XCTAssertEqual(coordinator.desiredExpandedDirectoryIDs(), [directory.id])
        XCTAssertTrue(coordinator.outlineView(outlineView, shouldSelectItem: node))

        guard case .select(let selectedItem)? = actions.first else {
            return XCTFail("Expected select action during search, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(selectedItem, directory)
    }

    func testDirectoryPrimaryClickDuringSearchOnlySelectsDirectory() {
        let child = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/main.swift"), isDirectory: false)
        let directory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [child]
        )
        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "main.swift",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        let outlineView = AppKitOutlineView()
        coordinator.outlineView = outlineView
        coordinator.refreshNodeCache(with: [directory])

        XCTAssertTrue(coordinator.handlePrimaryClick(on: coordinator.node(for: directory), event: keylessMouseEvent()))
        XCTAssertEqual(actions.count, 1)
        guard case .select(let item)? = actions.first else {
            return XCTFail("Expected select action, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(item, directory)
        XCTAssertFalse(coordinator.expandedIDs.contains(directory.id))
    }

    func testDesiredExpandedDirectoryIDsSkipDescendantsOfCollapsedDirectories() {
        let nestedDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources/Feature"),
            isDirectory: true
        )
        let rootDirectory = FileItem(
            url: URL(fileURLWithPath: "/tmp/project/Sources"),
            isDirectory: true,
            children: [nestedDirectory]
        )
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [rootDirectory],
            expandedIDs: [nestedDirectory.id],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { _ in },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()

        XCTAssertEqual(coordinator.desiredExpandedDirectoryIDs(), [])
    }

    func testRefreshNodeCacheUpdatesCollapsedDirectoryChildren() {
        let child = FileItem(url: URL(fileURLWithPath: "/tmp/project/Sources/main.swift"), isDirectory: false)
        let initialDirectory = makeDirectoryItem(path: "/tmp/project/Sources")
        let updatedDirectory = FileItem(
            url: initialDirectory.url,
            isDirectory: true,
            children: [child]
        )
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [initialDirectory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { _ in },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        _ = coordinator.node(for: initialDirectory)

        coordinator.refreshNodeCache(with: [updatedDirectory])

        XCTAssertEqual(coordinator.node(for: updatedDirectory).item.children, [child])
    }

    func testLoadingDirectoryUsesInlineLoadingNode() {
        let directory = makeDirectoryItem(path: "/tmp/project/Sources")
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [directory.id],
            loadingIDs: [directory.id],
            selectedID: nil,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { _ in },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        let outlineView = NSOutlineView()
        let node = coordinator.node(for: directory)

        XCTAssertEqual(coordinator.outlineView(outlineView, numberOfChildrenOfItem: node), 1)
        XCTAssertTrue(coordinator.outlineView(outlineView, child: 0, ofItem: node) is LoadingNode)
    }

    func testReturnKeyStartsRenameForSelectedDirectory() {
        let directory = makeDirectoryItem(path: "/tmp/project/Sources")
        var actions: [FileTreeAction] = []
        var renameText = ""
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: directory.id,
            renamingID: nil,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()
        coordinator.refreshNodeCache(with: [directory])

        XCTAssertTrue(coordinator.handleKeyDown(keyEvent(characters: "\r")))
        guard case .startRenaming(let item)? = actions.first else {
            return XCTFail("Expected startRenaming action, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(item, directory)
    }

    func testEscapeKeyCancelsActiveRename() {
        let directory = makeDirectoryItem(path: "/tmp/project/Sources")
        var actions: [FileTreeAction] = []
        var renameText = "Sources"
        let treeView = AppKitTreeView(
            rootItems: [directory],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: directory.id,
            renamingID: directory.id,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { actions.append($0) },
            onTransferDrop: { _ in false }
        )

        let coordinator = treeView.makeCoordinator()

        XCTAssertTrue(coordinator.handleKeyDown(keyEvent(characters: "\u{1b}")))
        guard case .cancelRename? = actions.first else {
            return XCTFail("Expected cancelRename action, got \(String(describing: actions.first)).")
        }
    }

    func testCoordinatorCanRestoreRenameFieldFocusAfterResponderSteal() {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/project/main.swift"), isDirectory: false)
        var renameText = file.displayName
        let treeView = AppKitTreeView(
            rootItems: [file],
            expandedIDs: [],
            loadingIDs: [],
            selectedID: file.id,
            renamingID: file.id,
            searchQuery: "",
            allowsScrolling: true,
            renameText: Binding(
                get: { renameText },
                set: { renameText = $0 }
            ),
            onAction: { _ in },
            onTransferDrop: { _ in false }
        )

        let (coordinator, _, outlineView, window) = makeMountedOutline(for: treeView)
        let row = outlineView.row(forItem: outlineView.item(atRow: 0))
        XCTAssertGreaterThanOrEqual(row, 0)
        let _ = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true)

        withExtendedLifetime(window) {
            window.makeFirstResponder(outlineView)
            coordinator.ensureRenameFieldFocused()
        }

        XCTAssertTrue(window.firstResponder is NSTextView)
    }

    func testCellViewUpdatePreservesInProgressRenameText() throws {
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/project/main.swift"), isDirectory: false)
        let cellView = AppKitTreeCellView(identifier: NSUserInterfaceItemIdentifier("TreeCell"))
        let node = TreeNode(item: file)

        cellView.configure(
            node: node,
            isSelected: false,
            isRenaming: true,
            isExpanded: false,
            searchQuery: "",
            scale: .default,
            onAction: { _ in },
            onDisclosureToggle: {},
            renameTextSetter: { _ in }
        )

        let labelField = try XCTUnwrap(
            cellView.subviews.compactMap { $0 as? NSTextField }.first(
                where: { $0.accessibilityIdentifier() == "explorer.rename.field" }
            )
        )
        labelField.stringValue = "renamed"

        cellView.update(
            node: node,
            isSelected: false,
            isRenaming: true,
            isExpanded: false,
            searchQuery: "",
            scale: .default
        )

        XCTAssertEqual(labelField.stringValue, "renamed")
    }

    private func makeDirectoryItem(path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), isDirectory: true)
    }

    private func makeMountedOutline(
        for treeView: AppKitTreeView
    ) -> (AppKitTreeView.Coordinator, AppKitTreeScrollView, AppKitOutlineView, NSWindow) {
        let coordinator = treeView.makeCoordinator()
        let scrollView = AppKitTreeScrollView()
        scrollView.configureScrolling(allowsScrolling: treeView.allowsScrolling)
        let outlineView = AppKitOutlineView(frame: NSRect(x: 0, y: 0, width: 320, height: 320))
        outlineView.headerView = nil
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 14
        outlineView.autoresizesOutlineColumn = true
        outlineView.selectionHighlightStyle = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator
        outlineView.contextMenuProvider = { [weak coordinator] item in
            coordinator?.buildContextMenu(for: item)
        }
        outlineView.rootContextMenuProvider = { [weak coordinator] in
            coordinator?.buildRootContextMenu()
        }
        outlineView.primaryClickHandler = { [weak coordinator] node, event in
            coordinator?.handlePrimaryClick(on: node, event: event) ?? false
        }
        outlineView.keyDownHandler = { [weak coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }

        coordinator.outlineView = outlineView
        coordinator.refreshNodeCache(with: treeView.rootItems)
        scrollView.documentView = outlineView
        outlineView.reloadData()
        coordinator.syncExpansionState()
        scrollView.invalidateIntrinsicContentSize()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.layoutIfNeeded()

        return (coordinator, scrollView, outlineView, window)
    }

    private func mouseEvent(
        at pointInOutline: NSPoint,
        in outlineView: AppKitOutlineView,
        clickCount: Int = 1
    ) -> NSEvent {
        let pointInWindow = outlineView.convert(pointInOutline, to: nil)

        return NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: pointInWindow,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: outlineView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    private func rightMouseEvent(
        at pointInOutline: NSPoint,
        in outlineView: AppKitOutlineView
    ) -> NSEvent {
        let pointInWindow = outlineView.convert(pointInOutline, to: nil)

        return NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: pointInWindow,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: outlineView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func mouseEvent(
        forRow row: Int,
        in outlineView: AppKitOutlineView,
        clickCount: Int = 1
    ) -> NSEvent {
        let rowRect = outlineView.rect(ofRow: row)
        let pointInOutline = NSPoint(x: rowRect.midX, y: rowRect.midY)
        return mouseEvent(at: pointInOutline, in: outlineView, clickCount: clickCount)
    }

    private func disclosureButton(forRow row: Int, in outlineView: AppKitOutlineView) -> NSButton? {
        guard row >= 0,
              let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) else {
            return nil
        }
        return cellView.subviews.compactMap { $0 as? NSButton }.first
    }

    private func keyEvent(characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: characters == "\u{1b}" ? 53 : 36
        )!
    }

    private func keylessMouseEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func assertSingleToggleExpansionAction(_ actions: [FileTreeAction], expectedItem: FileItem) {
        guard case .toggleExpansion(let item)? = actions.first else {
            return XCTFail("Expected toggleExpansion action, got \(String(describing: actions.first)).")
        }

        XCTAssertEqual(item, expectedItem)
    }

    private func assertSelectThenToggleActionSequence(_ actions: [FileTreeAction], expectedItem: FileItem) {
        guard case .select(let selectedItem)? = actions.first else {
            return XCTFail("Expected select action first, got \(String(describing: actions.first)).")
        }
        XCTAssertEqual(selectedItem, expectedItem)

        guard actions.count >= 2 else {
            return XCTFail("Expected toggleExpansion action second.")
        }

        guard case .toggleExpansion(let toggledItem) = actions[1] else {
            return XCTFail("Expected toggleExpansion action second, got \(actions[1]).")
        }
        XCTAssertEqual(toggledItem, expectedItem)
    }
}

private extension NSMenu {
    var itemTitlesExcludingSeparators: [String] {
        items.compactMap { $0.isSeparatorItem ? nil : $0.title }
    }
}
