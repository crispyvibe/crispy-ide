import Foundation

/// Pure logic for the unified ⌘1–⌘9 "focus-or-cycle" behavior.
/// Used by detailed view, terminal board, and Vibe Cast.
enum ProjectTerminalCycler {
    enum CycleResult: Equatable {
        /// Target project differs from current — focus it.
        case focusProject
        /// Target project is already focused — activate this terminal tab.
        case cycleTerminal(nextTabID: UUID)
        /// Nothing to do (single terminal or empty).
        case noOp
    }

    /// Determine whether to focus a project or cycle its terminal.
    ///
    /// - Parameters:
    ///   - isAlreadyFocused: Whether the target project is the currently focused/active project.
    ///   - tabIDs: Ordered terminal tab IDs for the target project.
    ///   - activeTabID: The currently active terminal tab ID in the target project (nil if none).
    /// - Returns: The action to take.
    static func resolve(
        isAlreadyFocused: Bool,
        tabIDs: [UUID],
        activeTabID: UUID?
    ) -> CycleResult {
        guard isAlreadyFocused else { return .focusProject }
        guard tabIDs.count > 1 else { return .noOp }

        let currentIndex = activeTabID
            .flatMap { id in tabIDs.firstIndex(of: id) } ?? 0
        let nextIndex = (currentIndex + 1) % tabIDs.count
        return .cycleTerminal(nextTabID: tabIDs[nextIndex])
    }
}
