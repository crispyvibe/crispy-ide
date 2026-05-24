import SwiftUI

extension VibeSpaceTerminalOnlyView {
    /// Window-fill color used behind the board canvas. The dedicated
    /// "Terminal Board" header chrome that previously lived in this file
    /// has been removed — the title bar's principal toolbar item now
    /// surfaces the vibespace / view / project breadcrumb that the
    /// in-canvas header used to show.
    var boardBackgroundColor: Color {
        appThemePalette.windowBackgroundColor
    }
}
