import AppKit
import Combine
import Foundation
import OSLog
import PDFKit
import SwiftUI

// MARK: - LaTeXCompiledPreviewView

/// Editable full-LaTeX page. Compiles the document with the local, offline TeX
/// toolchain (`LaTeXNativeCompiler`, `pdflatex -synctex=1`) and shows the real
/// PDF in a `PDFView`. Clicking on the rendered page maps back to the exact
/// source line via SyncTeX and opens a small inline editor right there; on
/// commit the document is rewritten and the page re-renders. That round-trip —
/// click the page, edit, see it re-typeset — is the "edit on the page" feel.
struct LaTeXCompiledPreviewView: NSViewRepresentable {
    let content: String
    var isBufferLoading: Bool = false
    var documentURL: URL? = nil
    /// Writes the full updated document source back to the buffer after an
    /// on-page edit (which then drives a re-render through `content`).
    var onEdit: ((String) -> Void)? = nil
    /// File path used to anchor comments (shared with Source/Edit views).
    @Environment(\.commentsFilePathEnvironment) private var commentsFilePath: String?

    static let recompileDebounce: TimeInterval = 0.7

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> CompiledPreviewContainerView {
        let container = CompiledPreviewContainerView()
        container.onPageClick = { [weak coordinator = context.coordinator] page, pdfPoint, windowPoint in
            coordinator?.handlePageClick(page: page, pdfPoint: pdfPoint, windowPoint: windowPoint)
        }
        context.coordinator.attach(container: container)
        context.coordinator.commentsFilePath = commentsFilePath

        guard LaTeXNativeCompiler.isToolchainAvailable else {
            container.showStatus(AppStrings.LaTeX.compilerUnavailable, isError: true)
            return container
        }
        container.showStatus(AppStrings.LaTeX.compiling, isError: false)
        context.coordinator.scheduleCompile(force: true)
        return container
    }

    func updateNSView(_ container: CompiledPreviewContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.commentsFilePath = commentsFilePath
        context.coordinator.scheduleCompile(force: false)
    }

    static func dismantleNSView(_ container: CompiledPreviewContainerView, coordinator: Coordinator) {
        coordinator.shutdown()
    }

    @MainActor
    final class Coordinator {
        var parent: LaTeXCompiledPreviewView
        var commentsFilePath: String?
        private weak var container: CompiledPreviewContainerView?
        private let compiler = LaTeXNativeCompiler()
        private var lastCompiledContent: String?
        private var pendingCompile: DispatchWorkItem?
        private var compileTask: Task<Void, Never>?
        private var currentPDFURL: URL?
        private var selectionObserver: NSObjectProtocol?
        private let logger = Logger(subsystem: "com.crispyvibe.app", category: "latex.compiled")

        init(parent: LaTeXCompiledPreviewView) { self.parent = parent }

        func attach(container: CompiledPreviewContainerView) {
            self.container = container
            // Mirror Source/Edit: selecting text offers an "Add comment" action.
            container.pdfView.onProbableSelection = { [weak self] in
                MainActor.assumeIsolated { self?.selectionChanged() }
            }
            selectionObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewSelectionChanged,
                object: container.pdfView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.selectionChanged() }
            }
        }

        /// Show/hide the floating "Comment" affordance as the PDF text selection
        /// changes. Mirrors the select-then-comment flow of the other surfaces.
        private func selectionChanged() {
            let selection = container?.pdfView.currentSelection
            let selectedText = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.debug("pdf-comment: selectionChanged file=\(self.commentsFilePath ?? "nil", privacy: .public) selLen=\(selectedText.count)")
            guard commentsFilePath != nil,
                  let pdfView = container?.pdfView,
                  let selection = pdfView.currentSelection,
                  !selectedText.isEmpty,
                  let page = selection.pages.first else {
                container?.hideCommentButton()
                return
            }
            let pageRect = selection.bounds(for: page)
            let viewRect = pdfView.convert(pageRect, from: page)
            container?.showCommentButton(near: viewRect) { [weak self] in self?.addCommentForSelection() }
        }

        /// Map the current PDF selection to source line(s) via SyncTeX, build a
        /// source-anchored CommentAnchor (identical schema to Source/Edit), and
        /// post `.commentsRequestAddForSelection` so the shared panel composer
        /// opens — keeping the experience the same across surfaces.
        private func addCommentForSelection() {
            guard let filePath = commentsFilePath,
                  let pdfView = container?.pdfView,
                  let selection = pdfView.currentSelection,
                  let pdfURL = currentPDFURL else { return }
            // What the user highlighted — shown as the quoted text in the panel,
            // matching the other surfaces.
            let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lineSelections = selection.selectionsByLine()
            guard let firstLine = lineSelections.first, let firstPage = firstLine.pages.first,
                  let lastLine = lineSelections.last, let lastPage = lastLine.pages.first else { return }
            let firstRect = firstLine.bounds(for: firstPage)
            let lastRect = lastLine.bounds(for: lastPage)
            guard let doc = pdfView.document else { return }
            let firstPageIndex = doc.index(for: firstPage)
            let lastPageIndex = doc.index(for: lastPage)
            let firstHeight = firstPage.bounds(for: .mediaBox).height
            let lastHeight = lastPage.bounds(for: .mediaBox).height
            // SyncTeX wants top-left origin: top of the first line, bottom of last.
            let startX = Double(firstRect.minX), startY = Double(firstHeight - firstRect.maxY)
            let endX = Double(lastRect.minX), endY = Double(lastHeight - lastRect.minY)

            Task { [weak self] in
                guard let self else { return }
                let startLoc = await self.compiler.sourceLocation(forPDFAt: pdfURL, page: firstPageIndex + 1, x: startX, y: startY)
                let endLoc = await self.compiler.sourceLocation(forPDFAt: pdfURL, page: lastPageIndex + 1, x: endX, y: endY)
                let startLine = startLoc?.line ?? 1
                let endLine = max(startLine, endLoc?.line ?? startLine)
                // Anchor to the SOURCE text of those lines (not the rendered
                // glyphs) so the anchor matches what Source/Edit produce.
                let lines = (self.lastCompiledContent ?? self.parent.content).components(separatedBy: "\n")
                let s = max(0, min(startLine - 1, lines.count - 1))
                let e = max(s, min(endLine - 1, lines.count - 1))
                // Quote what the user actually selected; fall back to the source
                // lines only if the rendered selection came back empty.
                let anchorText = selectedText.isEmpty ? lines[s...e].joined(separator: "\n") : selectedText
                let anchor = CommentAnchor(
                    startLine: s + 1,
                    startColumn: 1,
                    endLine: e + 1,
                    endColumn: max(1, (lines[e].count) + 1),
                    anchorHash: CommentAnchor.hash(anchorText),
                    anchorText: anchorText,
                    leadingContext: "",
                    trailingContext: ""
                )
                NotificationCenter.default.post(
                    name: .commentsRequestAddForSelection,
                    object: nil,
                    userInfo: anchor.notificationPayload(filePath: filePath)
                )
                self.container?.hideCommentButton()
                pdfView.clearSelection()
            }
        }

        func scheduleCompile(force: Bool) {
            guard LaTeXNativeCompiler.isToolchainAvailable, !parent.isBufferLoading else { return }
            guard force || parent.content != lastCompiledContent else { return }
            pendingCompile?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.compileNow() }
            pendingCompile = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + LaTeXCompiledPreviewView.recompileDebounce,
                execute: work
            )
        }

        private func compileNow() {
            let source = parent.content
            let documentURL = parent.documentURL
            lastCompiledContent = source
            container?.showStatus(AppStrings.LaTeX.compiling, isError: false)
            compileTask?.cancel()
            compileTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.compiler.compile(source: source, documentURL: documentURL)
                    if Task.isCancelled { return }
                    self.applyResult(result)
                } catch {
                    self.container?.showStatus(error.localizedDescription, isError: true)
                }
            }
        }

        private func applyResult(_ result: LaTeXNativeCompiler.CompileResult) {
            if let pdfURL = result.pdfURL, let document = PDFDocument(url: pdfURL) {
                cleanupPrevious(keeping: pdfURL)
                currentPDFURL = pdfURL
                container?.display(document: document)
            } else {
                container?.showCompileError(log: Self.tailLog(result.log))
            }
        }

        /// Click on the rendered page → SyncTeX source line → inline editor.
        func handlePageClick(page: Int, pdfPoint: CGPoint, windowPoint: CGPoint) {
            guard let pdfURL = currentPDFURL else { return }
            Task { [weak self] in
                guard let self else { return }
                guard let location = await self.compiler.sourceLocation(
                    forPDFAt: pdfURL, page: page, x: Double(pdfPoint.x), y: Double(pdfPoint.y)
                ) else { return }
                self.beginInlineEdit(atSourceLine: location.line, windowPoint: windowPoint)
            }
        }

        /// Open the inline editor for the source *block* (blank-line-delimited
        /// paragraph/environment) surrounding the SyncTeX line. Editing a whole
        /// block — not a single line — is a natural unit and stays useful even
        /// when SyncTeX lands a line or two off.
        private func beginInlineEdit(atSourceLine line: Int, windowPoint: CGPoint) {
            guard let source = lastCompiledContent else { return }
            let lines = source.components(separatedBy: "\n")
            guard !lines.isEmpty else { return }
            var idx = max(0, min(line - 1, lines.count - 1))
            // If SyncTeX landed on a blank line, snap to the nearest content line.
            if lines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                var d = 1
                while idx - d >= 0 || idx + d < lines.count {
                    if idx + d < lines.count, !lines[idx + d].trimmingCharacters(in: .whitespaces).isEmpty { idx += d; break }
                    if idx - d >= 0, !lines[idx - d].trimmingCharacters(in: .whitespaces).isEmpty { idx -= d; break }
                    d += 1
                }
            }
            // Expand to the surrounding blank-line-delimited block.
            var start = idx
            while start > 0, !lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty { start -= 1 }
            var end = idx
            while end < lines.count - 1, !lines[end + 1].trimmingCharacters(in: .whitespaces).isEmpty { end += 1 }
            logger.debug("edit-on-page: line \(line) -> block \(start + 1)...\(end + 1)")
            let blockText = lines[start...end].joined(separator: "\n")
            let rangeLabel = start == end
                ? "Editing line \(start + 1)"
                : "Editing lines \(start + 1)\u{2013}\(end + 1)"
            // Forward-map the block's first/last lines to PDF boxes so we can
            // highlight the exact region being edited, then open the editor.
            let mainTeXPath = currentPDFURL?.deletingLastPathComponent().appendingPathComponent("main.tex").path
            let pdfURL = currentPDFURL
            Task { [weak self] in
                guard let self else { return }
                var boxes: [LaTeXNativeCompiler.SyncBox] = []
                if let mainTeXPath, let pdfURL {
                    boxes = await self.compiler.forwardBoxes(forLine: start + 1, mainTeXPath: mainTeXPath, pdfURL: pdfURL)
                    if end != start {
                        boxes += await self.compiler.forwardBoxes(forLine: end + 1, mainTeXPath: mainTeXPath, pdfURL: pdfURL)
                    }
                }
                self.container?.showHighlight(syncBoxes: boxes)
                self.container?.beginBlockEdit(atWindowPoint: windowPoint, text: blockText, rangeLabel: rangeLabel) { [weak self] newText in
                    self?.commitBlockEdit(start: start, end: end, original: blockText, newText: newText)
                }
            }
        }

        /// Replace the edited block's source lines and push the document back to
        /// the buffer, which re-renders the page.
        private func commitBlockEdit(start: Int, end: Int, original: String, newText: String) {
            guard let source = lastCompiledContent else { return }
            var lines = source.components(separatedBy: "\n")
            guard start <= end, end < lines.count else { return }
            // Drift guard: only replace if the block still matches what we opened
            // (protects against a concurrent edit/recompile shifting line numbers).
            guard lines[start...end].joined(separator: "\n") == original else {
                logger.debug("edit-on-page: block drifted since open, skipping commit")
                return
            }
            let replacement = newText.components(separatedBy: "\n")
            if Array(lines[start...end]) == replacement { return }
            lines.replaceSubrange(start...end, with: replacement)
            parent.onEdit?(lines.joined(separator: "\n"))
        }

        func shutdown() {
            pendingCompile?.cancel()
            compileTask?.cancel()
            if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
            selectionObserver = nil
            cleanupPrevious(keeping: nil)
        }

        private func cleanupPrevious(keeping newURL: URL?) {
            guard let old = currentPDFURL, old != newURL else { return }
            try? FileManager.default.removeItem(at: old.deletingLastPathComponent())
        }

        private static func tailLog(_ log: String) -> String {
            log.split(separator: "\n").suffix(40).joined(separator: "\n")
        }
    }
}

// MARK: - LaTeXCompiledPane

/// Gates the compiled PDF preview on TeX availability. When the toolchain is
/// present it shows the live PDF; otherwise it shows an actionable empty-state
/// that tells the user exactly what to install, with a copy-able command, a
/// recheck, and a one-click switch to the dependency-free Edit tab.
struct LaTeXCompiledPane: View {
    let content: String
    var isBufferLoading: Bool = false
    var documentURL: URL? = nil
    var onEdit: ((String) -> Void)? = nil
    var onUseEditTab: () -> Void

    @State private var toolchainAvailable = LaTeXNativeCompiler.isToolchainAvailable

    var body: some View {
        if toolchainAvailable {
            LaTeXCompiledPreviewView(
                content: content,
                isBufferLoading: isBufferLoading,
                documentURL: documentURL,
                onEdit: onEdit
            )
        } else {
            missingToolchainView
        }
    }

    private var missingToolchainView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(AppStrings.LaTeX.toolchainMissingTitle)
                .font(.headline)
            Text(AppStrings.LaTeX.toolchainMissingBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack(spacing: 8) {
                Text(LaTeXNativeCompiler.installCommand)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LaTeXNativeCompiler.installCommand, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy install command")
            }

            HStack(spacing: 12) {
                Button(AppStrings.LaTeX.toolchainRecheck) {
                    toolchainAvailable = LaTeXNativeCompiler.isToolchainAvailable
                }
                .buttonStyle(.borderedProminent)
                Button(AppStrings.LaTeX.toolchainUseEdit) { onUseEditTab() }
                if let url = URL(string: "https://www.tug.org/mactex/morepackages.html") {
                    Link(AppStrings.LaTeX.toolchainGetBasicTeX, destination: url)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

