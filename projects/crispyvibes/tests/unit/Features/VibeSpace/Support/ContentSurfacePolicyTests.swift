import XCTest
@testable import CrispyVibes

/// Pure-policy coverage for the centralized content-presentation rulebook.
/// This table is the single source of truth that used to be duplicated (and
/// drifting) across every toolbar/sidebar "open X" action.
@MainActor
final class ContentSurfacePolicyTests: XCTestCase {

    // MARK: - Agent chat: view-aware

    func test_agentChat_inBoardMode_goesToBoardTile() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .agentChat, mode: .terminalOnly), .boardTile)
    }

    func test_agentChat_inDetailedMode_goesToDetailTab() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .agentChat, mode: .detailed), .detailTab)
    }

    // MARK: - Todos / VibeCast: float over the board, tab in detailed.

    func test_todos_spotlightInBoardMode_detailTabInDetailed() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .todos, mode: .terminalOnly), .spotlight)
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .todos, mode: .detailed), .detailTab)
    }

    func test_vibeCast_spotlightInBoardMode_detailTabInDetailed() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .vibeCast, mode: .terminalOnly), .spotlight)
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .vibeCast, mode: .detailed), .detailTab)
    }

    // MARK: - Conversation thread / file: docked preview over the board, tab otherwise

    func test_conversationThread_isDockedPreviewInBoardMode() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .conversationThread, mode: .terminalOnly), .dockedPreview)
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .conversationThread, mode: .detailed), .detailTab)
    }

    func test_file_isDockedPreviewInBoardMode() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .file, mode: .terminalOnly), .dockedPreview)
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .file, mode: .detailed), .detailTab)
    }

    // MARK: - Terminal: temporary always spotlights; otherwise board tile in
    // board mode, spotlight in detailed mode.

    func test_terminal_temporary_alwaysSpotlight() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .terminal(preferTemporary: true), mode: .terminalOnly), .spotlight)
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .terminal(preferTemporary: true), mode: .detailed), .spotlight)
    }

    func test_terminal_nonTemporary_boardTileInBoardMode_spotlightInDetailed() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .terminal(preferTemporary: false), mode: .terminalOnly), .boardTile)
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .terminal(preferTemporary: false), mode: .detailed), .spotlight)
    }

    func test_spotlightPin_boardTileInBoardMode_detailTabInDetailed() {
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .spotlightPin, mode: .terminalOnly), .boardTile)
        XCTAssertEqual(ContentSurfacePolicy.surface(for: .spotlightPin, mode: .detailed), .detailTab)
    }
}
