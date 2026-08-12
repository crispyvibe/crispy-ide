import Foundation

// MARK: - Centralized content presentation (the "where does this go?" rulebook)
//
// One rulebook decides how every piece of content is surfaced based on the
// active canvas mode, so the decision is never duplicated across toolbar /
// sidebar / use-case call sites (which is how it used to drift and produce
// "forces detailed view" bugs).
//
// - `ContentKind`          — the decision vocabulary (no payload), trivially testable.
// - `PresentableContent`   — payloads `VibeSpaceCanvasActionsCoordinator.present(_:)` dispatches.
// - `ContentSurface`       — the four places content can land.
// - `ContentSurfacePolicy` — the single (kind × mode → surface) source of truth.
//
// Adding a content type: add a `ContentKind` case, a policy row (+ test), and
// either a `PresentableContent` case routed through `present(_:)` or a call to
// `ContentSurfacePolicy.surface(for:mode:)` from a bespoke creation flow.

/// Decision-relevant discriminator for a piece of content — no payload — so the
/// surface policy is a pure function of kind × canvas mode and trivially
/// testable. The full vocabulary of things the app surfaces, including flows
/// with bespoke creation (terminal, file) that consult the policy directly
/// rather than going through `present(_:)`.
enum ContentKind: Equatable {
    case agentChat
    case conversationThread
    case todos
    case vibeLanes
    case vibeCast
    /// `preferTemporary` (the "Temporary Terminal" row) always spotlights,
    /// regardless of canvas mode.
    case terminal(preferTemporary: Bool)
    case file
    /// Promoting a temporary spotlight preview into a permanent surface.
    case spotlightPin
}

/// The payloads `VibeSpaceCanvasActionsCoordinator.present(_:)` knows how to
/// dispatch. A subset of `ContentKind`: terminal/file keep their specialized
/// creation flows and only consult the policy for the decision.
@MainActor
enum PresentableContent {
    case agentChat(project: AnyProjectSession?, preferredAgentID: String?)
    case conversationThread(ConversationThreadSummary)
    case todos
    case vibeLanes
    case vibeCast

    var kind: ContentKind {
        switch self {
        case .agentChat: return .agentChat
        case .conversationThread: return .conversationThread
        case .todos: return .todos
        case .vibeLanes: return .vibeLanes
        case .vibeCast: return .vibeCast
        }
    }
}

/// Where a piece of content is shown. Independent of the two-case canvas mode:
/// the same layout can host content as a detail tab, a board tile, a floating
/// docked preview, or a spotlight overlay.
enum ContentSurface: Equatable {
    case detailTab
    case boardTile
    case dockedPreview
    case spotlight
}

/// The single source of truth mapping (content × canvas mode) → surface. Pure
/// and synchronously testable. This is the rulebook that used to be duplicated
/// and drifting across every toolbar/sidebar/use-case action.
enum ContentSurfacePolicy {
    static func surface(for kind: ContentKind, mode: VibeSpaceCanvasMode) -> ContentSurface {
        switch kind {
        case .agentChat:
            // A new agent becomes a board tile in board mode, otherwise a tab.
            return mode == .terminalOnly ? .boardTile : .detailTab
        case .conversationThread, .file:
            // Surface as a floating preview over the board, otherwise a tab.
            return mode == .terminalOnly ? .dockedPreview : .detailTab
        case .todos, .vibeLanes, .vibeCast:
            // Float over the board (pin/dismiss like other previews); a detail
            // tab when already in detailed.
            return mode == .terminalOnly ? .spotlight : .detailTab
        case let .terminal(preferTemporary):
            // Temporary terminals always spotlight; otherwise a board tile in
            // board mode, or a spotlight terminal in detailed mode.
            if preferTemporary { return .spotlight }
            return mode == .terminalOnly ? .boardTile : .spotlight
        case .spotlightPin:
            // Pinning a preview: board tile in board mode, viewer tab otherwise.
            return mode == .terminalOnly ? .boardTile : .detailTab
        }
    }
}
