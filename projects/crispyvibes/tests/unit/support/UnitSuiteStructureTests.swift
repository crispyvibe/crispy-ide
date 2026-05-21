import XCTest

final class UnitSuiteStructureTests: XCTestCase {
    func testUnitAndBehavioralFoldersExist() {
        let testsFolder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // support
            .deletingLastPathComponent() // unit
            .deletingLastPathComponent() // tests

        let unitFolder = testsFolder.appendingPathComponent("unit")
        let behavioralFolder = testsFolder.appendingPathComponent("behavioral")

        XCTAssertTrue(FileManager.default.fileExists(atPath: unitFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: behavioralFolder.path))
    }
}
