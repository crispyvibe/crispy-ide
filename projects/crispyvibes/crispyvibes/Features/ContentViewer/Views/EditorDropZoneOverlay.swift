import SwiftUI

enum EditorDropZone: Equatable {
    case left, right, top, bottom, center
}

struct EditorDropZoneOverlay: View {
    @Environment(\.appThemePalette) private var palette
    let hoveredZone: EditorDropZone?

    var body: some View {
        GeometryReader { proxy in
            if let zone = hoveredZone {
                let rect = zoneRect(zone, in: proxy.size)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.accentColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(palette.accentColor.opacity(0.5), lineWidth: 2)
                    )
                    .padding(2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("content-viewer.drop-overlay")
    }

    /// Returns the frame for the highlighted zone — shows where the new pane will appear.
    private func zoneRect(_ zone: EditorDropZone, in size: CGSize) -> CGRect {
        let w = size.width
        let h = size.height
        switch zone {
        case .left:   return CGRect(x: 0, y: 0, width: w / 2, height: h)
        case .right:  return CGRect(x: w / 2, y: 0, width: w / 2, height: h)
        case .top:    return CGRect(x: 0, y: 0, width: w, height: h / 2)
        case .bottom: return CGRect(x: 0, y: h / 2, width: w, height: h / 2)
        case .center: return CGRect(x: 0, y: 0, width: w, height: h)
        }
    }

    /// IDE-style zone detection: 3-column grid, center column splits top/bottom.
    /// Uses pixel coordinates with y=0 at top (SwiftUI convention).
    static func zone(at location: CGPoint, in size: CGSize) -> EditorDropZone {
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return .center }

        let x = location.x
        let y = location.y
        let thirdW = w / 3

        // Edge threshold: 10% from each edge → center (no split)
        let edgeW = w * 0.1
        let edgeH = h * 0.1
        if x > edgeW, x < w - edgeW, y > edgeH, y < h - edgeH {
            // Inside the center region — use the 3-column grid
        } else {
            // Very close to an edge — always split toward that edge
        }

        // 3-column layout (split-zone preferSplitVertically):
        //  LEFT 33%  |  center 33%  |  RIGHT 33%
        //            | top / bottom |
        if x < thirdW {
            return .left
        } else if x > thirdW * 2 {
            return .right
        } else if y < h / 2 {
            return .top
        } else {
            return .bottom
        }
    }
}
