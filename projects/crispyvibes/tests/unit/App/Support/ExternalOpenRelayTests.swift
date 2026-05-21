import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ExternalOpenRelayTests: XCTestCase {
    override func tearDown() {
        _ = ExternalOpenRelay.drain()
        super.tearDown()
    }

    func testSubmitPostsAvailabilityNotification() {
        let expectation = expectation(forNotification: .openExternalPaths, object: nil)

        ExternalOpenRelay.submit(
            .init(urls: [URL(fileURLWithPath: "/tmp/notify.txt")], preferTerminal: false)
        )

        wait(for: [expectation], timeout: 1)
    }
}
