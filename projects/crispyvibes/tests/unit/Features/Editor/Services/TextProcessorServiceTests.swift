import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class TextProcessorServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var originalEnvironment: [String: String?] = [:]
    private var originalUserDefaults: [String: Any?] = [:]

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-text-processor")
        try installKiroStub(in: tempRoot)
        captureEnvironment(keys: [
            "PATH",
            "CRISPYVIBES_KIRO_REPHRASE_AGENT",
            "CRISPYVIBES_KIRO_RESEARCH_AGENT",
            "CRISPYVIBES_KIRO_AGENT",
            "CRISPYVIBES_TEST_KIRO_MODE",
            "CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS"
        ])
        captureDefaults(keys: [
            AppPreferences.textServiceCLIProfileKey,
            AppPreferences.textServiceCLICommandKey,
            AppPreferences.textServiceCLIArgumentsKey,
            AppPreferences.textServicePassAgentFlagKey,
            AppPreferences.textServiceDefaultAgentKey,
            AppPreferences.textServiceRephrasePromptKey,
            AppPreferences.textServiceResearchPromptKey
        ])
        setenv("PATH", tempRoot.path, 1)
        unsetenv("CRISPYVIBES_KIRO_REPHRASE_AGENT")
        unsetenv("CRISPYVIBES_KIRO_RESEARCH_AGENT")
        unsetenv("CRISPYVIBES_KIRO_AGENT")
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "success", 1)
        unsetenv("CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS")
        UserDefaults.standard.removeObject(forKey: AppPreferences.textServiceCLIProfileKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.textServiceCLICommandKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.textServiceCLIArgumentsKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.textServicePassAgentFlagKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.textServiceDefaultAgentKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.textServiceRephrasePromptKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.textServiceResearchPromptKey)
    }

    override func tearDownWithError() throws {
        restoreEnvironment()
        restoreDefaults()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testRephraseMissingInputSetsErrorMessage() {
        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNotNil(errorMessage)
        XCTAssertTrue((errorMessage as String?)?.contains("No selected text") == true)
    }

    func testRephraseUsesConfiguredAgentAndWritesResponse() {
        setenv("CRISPYVIBES_KIRO_REPHRASE_AGENT", "unit-agent", 1)
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "success", 1)

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(errorMessage)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("rewritten-by-unit-agent"))
        XCTAssertTrue(output.contains("line-two"))
        XCTAssertFalse(output.contains("\u{001B}["))
    }

    func testRephraseUsesConfiguredCLICommandFromAppSettings() throws {
        let customCommand = "custom-kiro-cli"
        try? FileManager.default.removeItem(at: tempRoot.appendingPathComponent("kiro-cli"))
        try installKiroStub(named: customCommand, in: tempRoot)
        UserDefaults.standard.set(customCommand, forKey: AppPreferences.textServiceCLICommandKey)

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(errorMessage)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("rewritten-by-none"))
    }

    func testResearchCommandFailurePropagatesExitCodeAndDetails() {
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "fail", 1)
        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.research(pasteboard, userData: nil, error: &errorMessage)

        let error = errorMessage as String?
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("17") == true)
        XCTAssertTrue(error?.contains("simulated failure") == true)
    }

    func testResearchEmptyResponseReportsFriendlyError() {
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "empty", 1)
        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.research(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNotNil(errorMessage)
        XCTAssertTrue((errorMessage as String?)?.contains("empty response") == true)
    }

    func testRephraseOmitsAgentWhenNotConfigured() {
        unsetenv("CRISPYVIBES_KIRO_REPHRASE_AGENT")
        unsetenv("CRISPYVIBES_KIRO_AGENT")
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "success", 1)

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        service.rephrase(pasteboard)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("rewritten-by-none"))
    }

    func testRephraseFallsBackToUserDefaultsAgentWhenEnvironmentMissing() {
        unsetenv("CRISPYVIBES_KIRO_REPHRASE_AGENT")
        unsetenv("CRISPYVIBES_KIRO_AGENT")
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "success", 1)
        UserDefaults.standard.set("defaults-agent", forKey: AppPreferences.textServiceDefaultAgentKey)

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        service.rephrase(pasteboard)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("rewritten-by-defaults-agent"))
    }

    func testRephraseCanDisableAgentFlagForAlternativeCLIs() {
        setenv("CRISPYVIBES_KIRO_REPHRASE_AGENT", "preferred-agent", 1)
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "agent-fallback", 1)
        UserDefaults.standard.set(false, forKey: AppPreferences.textServicePassAgentFlagKey)

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(errorMessage)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("rewritten-by-none"))
    }

    func testRephraseAllowsEmptyCLIArgumentsWithoutFallingBackToDefaults() {
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "assert-no-chat-arg", 1)
        UserDefaults.standard.set("", forKey: AppPreferences.textServiceCLIArgumentsKey)
        UserDefaults.standard.set(false, forKey: AppPreferences.textServicePassAgentFlagKey)

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(errorMessage)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("rewritten-by-none"))
    }

    func testRephraseRetriesWithoutAgentWhenPreferredAgentFails() {
        setenv("CRISPYVIBES_KIRO_REPHRASE_AGENT", "preferred-agent", 1)
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "agent-fallback", 1)

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(errorMessage)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("rewritten-by-none"))
    }

    func testRephrasePromptTemplateSupportsPlaceholder() {
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "echo-prompt", 1)
        UserDefaults.standard.set(
            "Please rewrite this: {{text}}",
            forKey: AppPreferences.textServiceRephrasePromptKey
        )

        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(errorMessage)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("Please rewrite this: Original text"))
        XCTAssertFalse(output.contains("\nText:\n"))
    }

    func testRephraseTimesOutLongRunningCommand() {
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "sleep", 1)
        setenv("CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS", "0.1", 1)
        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original text", forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNotNil(errorMessage)
        XCTAssertTrue((errorMessage as String?)?.contains("timed out") == true)
    }

    func testRephraseSplitsLargeInputIntoPromptChunks() {
        setenv("CRISPYVIBES_TEST_KIRO_MODE", "echo-prompt", 1)
        let largeInput = String(repeating: "0123456789", count: 900)
        let service = TextProcessorService()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("unit-text-processor-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(largeInput, forType: .string)

        var errorMessage: NSString?
        service.rephrase(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(errorMessage)
        let output = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(output.contains("Chunk 1:"))
        XCTAssertTrue(output.contains("Chunk 2:"))
    }

    func testInfoPlistRegistersTextServicesAndPortName() throws {
        let infoPlist = try loadRepositoryInfoPlist()
        let services = try XCTUnwrap(infoPlist["NSServices"] as? [[String: Any]])
        XCTAssertEqual(services.count, 3)
        let expectedPortName = try XCTUnwrap(infoPlist["CFBundleIdentifier"] as? String)
        let expectedDisplayName = try XCTUnwrap(
            (infoPlist["CFBundleDisplayName"] as? String) ?? (infoPlist["CFBundleName"] as? String)
        )

        let messages = Set(services.compactMap { $0["NSMessage"] as? String })
        XCTAssertEqual(messages, Set(["rephrase", "research", "openInTerminal"]))

        for service in services {
            let portName = service["NSPortName"] as? String
            XCTAssertEqual(portName, expectedPortName)

            let menuTitle = ((service["NSMenuItem"] as? [String: Any])?["default"] as? String) ?? ""
            XCTAssertTrue(menuTitle.hasPrefix("\(expectedDisplayName): "))

            let message = service["NSMessage"] as? String
            switch message {
            case "rephrase", "research":
                let sendTypes = service["NSSendTypes"] as? [String] ?? []
                let returnTypes = service["NSReturnTypes"] as? [String] ?? []
                XCTAssertTrue(sendTypes.contains("public.utf8-plain-text"))
                XCTAssertTrue(returnTypes.contains("public.utf8-plain-text"))
            case "openInTerminal":
                let sendFileTypes = service["NSSendFileTypes"] as? [String] ?? []
                XCTAssertTrue(sendFileTypes.contains("public.folder"))
                XCTAssertTrue(sendFileTypes.contains("public.shell-script"))
            default:
                XCTFail("Unexpected service message: \(String(describing: message))")
            }
        }
    }

    private func installKiroStub(named commandName: String = "kiro-cli", in root: URL) throws {
        let executableURL = root.appendingPathComponent(commandName)
        let script = """
        #!/bin/sh
        mode="${CRISPYVIBES_TEST_KIRO_MODE:-success}"
        agent="none"
        prompt=""
        saw_chat=0
        while [ "$#" -gt 0 ]; do
            if [ "$1" = "--agent" ] && [ "$#" -ge 2 ]; then
                agent="$2"
                shift 2
                continue
            fi
            if [ "$1" = "chat" ]; then
                saw_chat=1
            fi
            prompt="$1"
            shift
        done

        case "$mode" in
            success)
                printf '\\033[32mbootstrap\\033[0m\\n'
                printf '> rewritten-by-%s\\n' "$agent"
                printf 'line-two\\r\\n'
                printf '\\342\\226\\270 Time: 0.1s\\n'
                exit 0
                ;;
            agent-fallback)
                if [ "$agent" != "none" ]; then
                    printf 'agent-specific failure\\n' >&2
                    exit 9
                fi
                printf '> rewritten-by-%s\\n' "$agent"
                printf '\\342\\226\\270 Time: 0.1s\\n'
                exit 0
                ;;
            empty)
                printf '>   \\n'
                printf '\\342\\226\\270 Time: 0.1s\\n'
                exit 0
                ;;
            fail)
                printf 'simulated failure\\n' >&2
                exit 17
                ;;
            assert-no-chat-arg)
                if [ "$saw_chat" -eq 1 ]; then
                    printf 'unexpected chat arg\\n' >&2
                    exit 31
                fi
                printf '> rewritten-by-%s\\n' "$agent"
                printf '\\342\\226\\270 Time: 0.1s\\n'
                exit 0
                ;;
            echo-prompt)
                printf '> %s\\n' "$prompt"
                printf '\\342\\226\\270 Time: 0.1s\\n'
                exit 0
                ;;
            sleep)
                sleep 5
                printf '> delayed\\n'
                printf '\\342\\226\\270 Time: 5.0s\\n'
                exit 0
                ;;
            *)
                printf 'unknown mode\\n' >&2
                exit 3
                ;;
        esac
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )
    }

    private func captureEnvironment(keys: [String]) {
        for key in keys {
            originalEnvironment[key] = ProcessInfo.processInfo.environment[key]
        }
    }

    private func restoreEnvironment() {
        for (key, value) in originalEnvironment {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }

    private func captureDefaults(keys: [String]) {
        originalUserDefaults = captureUserDefaultsSnapshot(keys: keys)
    }

    private func restoreDefaults() {
        restoreUserDefaultsSnapshot(originalUserDefaults)
    }
}
