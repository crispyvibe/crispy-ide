import SwiftUI

extension VibeSpaceTerminalOnlyView {
    var surfaceLayout: VibeSpaceTerminalBoardLayout {
        boardStore.layout(for: surfaceID)
    }

    var projectPathSnapshot: [String] {
        projects.map { $0.rootURL.standardizedFileURL.path }
    }

    func navigateSpatially(_ direction: BoardNavigationDirection) {
        guard case .idle = interactionController.state else { return }
        guard currentBoardSize.width > 0, currentBoardSize.height > 0 else { return }
        let layout = surfaceLayout
        let metrics = VibeSpaceTerminalBoardMetrics(size: currentBoardSize, layout: layout)
        var tileFrames: [UUID: CGRect] = [:]
        for tile in layout.tiles {
            tileFrames[tile.id] = metrics.frame(for: tile)
        }
        guard let targetID = BoardSpatialNavigation.resolve(
            direction: direction,
            activeTileID: layout.activeTileID,
            layout: layout,
            tileFrames: tileFrames
        ) else { return }
        boardStore.activateTile(targetID, requestFocus: true, surfaceID: surfaceID)
    }

    func updateBoardInteractionMetrics(size: CGSize, layout: VibeSpaceTerminalBoardLayout) {
        guard size.width > 0, size.height > 0 else { return }
        currentBoardSize = size
        let metrics = VibeSpaceTerminalBoardMetrics(size: size, layout: layout)
        let hitTestContext = BoardHitTesting.context(from: layout, boardSize: size)
        interactionController.metricsProvider = BoardMetricsAdapter(
            metrics: metrics,
            layout: layout,
            hitTestContext: hitTestContext
        )
    }
}
