import Foundation

/// Bundle of dependencies the VibeSpaces settings panel needs from the host
/// (ContentView). Mirrors the pattern used by `AppShortcutVibeSpaceContext`
/// so AppSettingsSheetView's init signature stays uniform.
@MainActor
struct AppSettingsVibeSpacesContext {
    /// Catalog source: lists, loads, deletes vibespaces.
    let vibespaceManagement: VibeSpaceManaging
    /// Open the chosen vibespace. Caller is responsible for dismissing the
    /// settings surface (so the user lands on the newly opened vibespace).
    let onOpenVibeSpace: (VibeSpaceConfigFile) -> Void
    /// Bulk-delete the given vibespace IDs. Caller is responsible for
    /// closing any active session that maps to a deleted ID and refreshing
    /// dependent state.
    let onDeleteVibeSpaces: (Set<UUID>) -> Void
}
