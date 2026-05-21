import AppKit
import Foundation
import SwiftTerm

@MainActor
final class SwiftTermTerminalEngine: NSObject, TerminalSessionEngine, @preconcurrency LocalProcessTerminalViewDelegate {
    private let terminalView = MonitoredTerminalView(frame: .zero)
    private weak var delegate: (any TerminalSessionEngineDelegate)?
    private let terminalServices: TerminalServices
    var sessionID: UUID? {
        didSet { terminalView.ownerSessionID = sessionID }
    }

    init(terminalServices: TerminalServices) {
        self.terminalServices = terminalServices
        super.init()
        terminalView.focusCoordinator = terminalServices.focusCoordinator
        terminalView.vibespaceInteraction = terminalServices.vibespaceInteraction
    }

    var hostedView: NSView { terminalView }
    var effectiveAppearance: NSAppearance { terminalView.effectiveAppearance }
    var font: NSFont {
        get { terminalView.font }
        set { terminalView.font = newValue }
    }
    var processIsRunning: Bool { terminalView.process.running }
    var shellProcessID: Int32 { terminalView.process.shellPid }
    var debugIdentifier: String { String(describing: ObjectIdentifier(terminalView)) }

    func configure(
        delegate: any TerminalSessionEngineDelegate,
        initialFont: NSFont,
        optionAsMetaKey: Bool,
        historySize: Int
    ) {
        self.delegate = delegate
        terminalView.processDelegate = self
        terminalView.autoresizingMask = [.width, .height]
        terminalView.font = initialFont
        terminalView.optionAsMetaKey = optionAsMetaKey
        let terminal = terminalView.getTerminal()
        terminal.changeHistorySize(historySize)
        terminal.options.kittyImageCacheLimitBytes = TerminalMemoryBudget.swiftTermKittyImageCacheLimitBytes
        terminalView.onRenderableOutputReceived = { [weak self] renderableSample in
            guard let self else { return }
            self.delegate?.terminalEngine(self, didReceiveRenderableOutput: renderableSample)
        }
        terminalView.onSignificantOutputReceived = { [weak self] in
            guard let self else { return }
            self.delegate?.terminalEngineDidReceiveSignificantOutput(self)
        }
    }

    func startProcess(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String
    ) {
        terminalView.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            currentDirectory: currentDirectory
        )
    }

    func terminate() {
        terminalView.terminate()
        terminalView.onRenderableOutputReceived = nil
        terminalView.onSignificantOutputReceived = nil
        terminalView.onSplitTerminalRequested = nil
        terminalView.onTemporaryTerminalRequested = nil
        terminalView.onLinkTargetActivated = nil
        terminalView.onFileSystemTargetActivated = nil
        terminalView.onInlineTriggerTextInput = nil
        terminalView.onInlineTriggerCommand = nil
        terminalView.currentDirectoryProvider = nil
    }

    func copySelection() {
        terminalView.copy(self)
    }

    func pasteFromClipboard() {
        terminalView.paste(self)
    }

    func send(text: String) {
        terminalView.send(txt: text)
    }

    func typeCharacters(_ text: String) {
        terminalView.send(txt: text)
    }

    func pressEnter() {
        terminalView.send(txt: "\r")
    }

    func pressSubmitVariant(_ variant: TerminalSubmitVariant) {
        switch variant {
        case .returnKey, .keypadEnter, .controlM, .carriageReturnByte:
            terminalView.send(txt: "\r")
        case .controlJ, .lineFeedByte:
            terminalView.send(txt: "\n")
        }
    }

    func registerOscHandler(code: Int, handler: @escaping (ArraySlice<UInt8>) -> Void) {
        terminalView.getTerminal().registerOscHandler(code: code, handler: handler)
    }

    func currentDimensions() -> (cols: Int, rows: Int) {
        let dims = terminalView.getTerminal().getDims()
        return (cols: dims.cols, rows: dims.rows)
    }

    func resize(cols: Int, rows: Int) {
        terminalView.getTerminal().resize(cols: cols, rows: rows)
    }

    func updateActionHandlers(_ handlers: TerminalSessionActionHandlers) {
        terminalView.onSplitTerminalRequested = handlers.onSplitTerminalRequested
        terminalView.onTemporaryTerminalRequested = handlers.onTemporaryTerminalRequested
        terminalView.onLinkTargetActivated = handlers.onLinkTargetActivated
        terminalView.onFileSystemTargetActivated = handlers.onFileSystemTargetActivated
        terminalView.onInlineTriggerTextInput = handlers.onInlineTriggerTextInput
        terminalView.onInlineTriggerCommand = handlers.onInlineTriggerCommand
        terminalView.currentDirectoryProvider = handlers.currentDirectoryProvider
    }

    func applyThemePalette(_ palette: AppThemePalette) {
        terminalView.configureNativeColors()
        terminalView.nativeBackgroundColor = palette.canvasBackground.nsColor
        terminalView.nativeForegroundColor = palette.terminalForeground.nsColor
        terminalView.caretColor = palette.terminalCaret.nsColor
        terminalView.selectedTextBackgroundColor = palette.terminalSelectionBackground.nsColor
        terminalView.layer?.backgroundColor = terminalView.nativeBackgroundColor.cgColor
        terminalView.colorChanged(source: terminalView.getTerminal(), idx: nil)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        delegate?.terminalEngine(self, didChangeSizeToCols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        delegate?.terminalEngine(self, didChangeTitle: title)
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        delegate?.terminalEngine(self, didUpdateCurrentDirectory: directory)
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        delegate?.terminalEngine(self, didTerminateWithExitCode: exitCode)
    }
}
