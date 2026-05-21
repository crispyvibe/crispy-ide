import Foundation

/// Captures external state that needs to be embedded into `VibeSpaceTerminalBoardState`
/// at persistence time. External sources (browser VMs, etc.) own their state; the board
/// state only carries the descriptors needed to render. At save time, the store asks the
/// providers for the current snapshot of external state and writes it into the on-disk
/// state so it can be restored on relaunch.
///
/// Providers are pure capture functions. They are not invoked to cause side effects.
@MainActor
struct BoardSnapshotProviders {
    /// Returns the current URL for a browser tile, if the provider knows one.
    /// When non-nil, replaces the tile's `contentKind` URL on persist.
    var browserCurrentURL: (UUID) -> URL?

    /// Returns the current browser session snapshot for a tile, if the provider knows one.
    /// When non-nil, replaces the tile's `browserSession` on persist. Returning nil preserves
    /// whatever snapshot the state already carries (so restore-from-disk survives provider
    /// absence).
    var browserSession: (UUID) -> BrowserSessionSnapshot?

    static let noop = BoardSnapshotProviders(
        browserCurrentURL: { _ in nil },
        browserSession: { _ in nil }
    )

    /// Providers backed by a `DockedBrowserCoordinator`. If the coordinator is nil,
    /// behaves like `.noop`. The coordinator is captured weakly so it does not keep
    /// the browser store alive beyond its owner's lifetime.
    static func browserBacked(coordinator: DockedBrowserCoordinator?) -> BoardSnapshotProviders {
        guard let coordinator else { return .noop }
        return BoardSnapshotProviders(
            browserCurrentURL: { [weak coordinator] tileID in
                coordinator?.currentURLs(for: [tileID])[tileID]
            },
            browserSession: { [weak coordinator] tileID in
                coordinator?.snapshotBrowserSessions(for: [tileID])[tileID]
            }
        )
    }

    /// Returns a copy of `state` with per-tile browser fields refreshed from the providers.
    /// Non-browser tiles and non-browser fields are left untouched.
    func enriched(_ state: VibeSpaceTerminalBoardState) -> VibeSpaceTerminalBoardState {
        var next = state
        for surfaceIndex in next.surfaces.indices {
            for columnIndex in next.surfaces[surfaceIndex].layout.columns.indices {
                for tileIndex in next.surfaces[surfaceIndex].layout.columns[columnIndex].tiles.indices {
                    next.surfaces[surfaceIndex].layout.columns[columnIndex].tiles[tileIndex] =
                        enrichTile(next.surfaces[surfaceIndex].layout.columns[columnIndex].tiles[tileIndex])
                }
            }
            for tileIndex in next.surfaces[surfaceIndex].layout.minimizedTiles.indices {
                next.surfaces[surfaceIndex].layout.minimizedTiles[tileIndex] =
                    enrichTile(next.surfaces[surfaceIndex].layout.minimizedTiles[tileIndex])
            }
        }
        return next
    }

    private func enrichTile(_ tile: VibeSpaceTerminalBoardTile) -> VibeSpaceTerminalBoardTile {
        guard tile.isBrowser else { return tile }
        var next = tile
        if let currentURL = browserCurrentURL(tile.id) {
            next.contentKind = .browser(currentURL)
        }
        if let snapshot = browserSession(tile.id) {
            next.browserSession = snapshot
        }
        return next
    }
}
