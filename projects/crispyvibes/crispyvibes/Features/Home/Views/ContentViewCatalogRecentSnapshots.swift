import SwiftUI

extension ContentView {
    private var maximumRecentVibeSpaceCount: Int { 12 }

    var recentVibeSpaceConfigsForDisplay: [VibeSpaceConfigFile] {
        vibespaceManagement.recentVibeSpaceConfigs(limit: maximumRecentVibeSpaceCount)
    }

    func rememberRecentVibeSpace(_ vibespaceID: UUID) {
        vibespaceManagement.touchRecent(vibespaceID)
    }
}
