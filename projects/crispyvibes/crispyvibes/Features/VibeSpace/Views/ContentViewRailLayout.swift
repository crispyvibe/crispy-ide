import SwiftUI

extension ContentView {
    private var stackedRailItemSpacing: CGFloat {
        8
    }

    private var stackedRailOuterPadding: CGFloat {
        12
    }

    func stackedCardHeight(for count: Int, availableHeight: CGFloat, isHorizontal: Bool) -> CGFloat {
        if isHorizontal {
            return max(availableHeight - stackedRailOuterPadding, 120)
        }
        guard count > 0 else { return 150 }
        let spacing = stackedRailItemSpacing
        let totalSpacing = CGFloat(max(count - 1, 0)) * spacing
        let usableHeight = max(availableHeight - stackedRailOuterPadding - totalSpacing, 1)
        let rawHeight = usableHeight / CGFloat(count)
        return max(rawHeight, 120)
    }

    func stackedCardWidth(for count: Int, availableWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 260 }
        let spacing = stackedRailItemSpacing
        let totalSpacing = CGFloat(max(count - 1, 0)) * spacing
        let usableWidth = max(availableWidth - stackedRailOuterPadding - totalSpacing, 1)
        let rawWidth = usableWidth / CGFloat(count)
        return max(rawWidth, 220)
    }
}
