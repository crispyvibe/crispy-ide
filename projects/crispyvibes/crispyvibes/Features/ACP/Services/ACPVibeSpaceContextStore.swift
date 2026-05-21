import Combine
import Foundation

@MainActor
final class ACPVibeSpaceContextStore: ObservableObject {
    @Published private(set) var vibespaceID: UUID?
    @Published private(set) var focusedProjectIdentifier: String?
    @Published private(set) var focusedProjectDisplayName: String?
    @Published private(set) var focusedProjectRootPath: String?

    private weak var focusedProjectReference: AnyProjectSession?

    var focusedProject: AnyProjectSession? { focusedProjectReference }

    func update(vibespaceID: UUID?, focusedProject: AnyProjectSession?) {
        self.vibespaceID = vibespaceID
        self.focusedProjectReference = focusedProject
        self.focusedProjectIdentifier = focusedProject?.projectIdentifier
        self.focusedProjectDisplayName = focusedProject?.title
        self.focusedProjectRootPath = focusedProject?.rootURL.standardizedFileURL.path
    }
}
