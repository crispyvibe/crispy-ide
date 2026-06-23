import AppKit
import Combine
import Foundation
import OSLog
import PDFKit
import SwiftUI
import WebKit

// MARK: - ExternalTool

/// Locates and runs an external CLI converter (typst / dot / asciidoctor) off
/// the main thread. Mirrors the LaTeX toolchain discovery: these are the
/// per-format engines, found on disk, run with no network.
enum ExternalTool {
    /// Directories searched for converter binaries, best-first.
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/Library/TeX/texbin", "/usr/bin"]

    static func resolve(_ name: String) -> URL? {
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func isAvailable(_ name: String) -> Bool { resolve(name) != nil }

    struct Output { let status: Int32; let stdout: Data; let log: String }

    /// Run `tool args` in `cwd`. Returns exit status, stdout bytes, and merged stderr/stdout text.
    /// Terminates the process if the surrounding Task is cancelled or `timeout`
    /// elapses, so a runaway/looping compile can't hang or pile up.
    static func run(_ tool: URL, _ args: [String], cwd: URL?, env extra: [String: String] = [:], timeout: TimeInterval = 30) async -> Output {
        let process = Process()
        process.executableURL = tool
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPaths.joined(separator: ":") + ":" + (environment["PATH"] ?? "")
        for (key, value) in extra { environment[key] = value }
        process.environment = environment

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Output, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                    do {
                        try process.run()
                    } catch {
                        watchdog.cancel()
                        continuation.resume(returning: Output(status: -1, stdout: Data(), log: "\(error)"))
                        return
                    }
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    watchdog.cancel()
                    continuation.resume(returning: Output(
                        status: process.terminationStatus,
                        stdout: outData,
                        log: String(data: errData, encoding: .utf8) ?? ""
                    ))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// A fresh scratch directory for one compile.
    static func makeScratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("crispyvibes-preview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Format compilers

/// Produces a PDF from Typst source (`typst compile`).
struct TypstPreviewCompiler {
    static var isAvailable: Bool { ExternalTool.isAvailable("typst") }

    func compile(source: String, documentURL: URL?) async -> (pdfURL: URL?, log: String) {
        guard let typst = ExternalTool.resolve("typst") else { return (nil, "typst not found") }
        do {
            let dir = try ExternalTool.makeScratchDir()
            let input = dir.appendingPathComponent("main.typ")
            try source.data(using: .utf8)?.write(to: input)
            let output = dir.appendingPathComponent("main.pdf")
            let result = await ExternalTool.run(
                typst, ["compile", "--root", dir.path, input.path, output.path], cwd: dir
            )
            let ok = result.status == 0 && FileManager.default.fileExists(atPath: output.path)
            if !ok { try? FileManager.default.removeItem(at: dir) }
            return (ok ? output : nil, result.log)
        } catch {
            return (nil, "\(error)")
        }
    }
}

/// Produces a PDF from a Graphviz `.dot` graph (`dot -Tpdf`).
struct GraphvizPreviewCompiler {
    static var isAvailable: Bool { ExternalTool.isAvailable("dot") }

    func compile(source: String, documentURL: URL?) async -> (pdfURL: URL?, log: String) {
        guard let dot = ExternalTool.resolve("dot") else { return (nil, "dot not found") }
        do {
            let dir = try ExternalTool.makeScratchDir()
            let input = dir.appendingPathComponent("graph.dot")
            try source.data(using: .utf8)?.write(to: input)
            let output = dir.appendingPathComponent("graph.pdf")
            let result = await ExternalTool.run(dot, ["-Tpdf", input.path, "-o", output.path], cwd: dir)
            let ok = result.status == 0 && FileManager.default.fileExists(atPath: output.path)
            if !ok { try? FileManager.default.removeItem(at: dir) }
            return (ok ? output : nil, result.log)
        } catch {
            return (nil, "\(error)")
        }
    }
}

/// Produces standalone HTML from AsciiDoc (`asciidoctor`).
struct AsciiDoctorPreviewCompiler {
    static var isAvailable: Bool { ExternalTool.isAvailable("asciidoctor") }

    func compile(source: String, documentURL: URL?) async -> (html: String?, log: String) {
        guard let tool = ExternalTool.resolve("asciidoctor") else { return (nil, "asciidoctor not found") }
        do {
            let dir = try ExternalTool.makeScratchDir()
            defer { try? FileManager.default.removeItem(at: dir) } // output is stdout; nothing to keep
            let input = dir.appendingPathComponent("doc.adoc")
            try source.data(using: .utf8)?.write(to: input)
            // -o - → emit the standalone HTML (embedded default stylesheet) to stdout.
            let baseDir = documentURL?.deletingLastPathComponent().path ?? dir.path
            let result = await ExternalTool.run(
                tool, ["--base-dir", baseDir, "-o", "-", input.path], cwd: dir
            )
            let html = String(data: result.stdout, encoding: .utf8)
            return (result.status == 0 ? html : nil, result.log)
        } catch {
            return (nil, "\(error)")
        }
    }
}

// MARK: - CompiledPDFPreviewView (generic, read-only)

/// Renders any source that compiles to a PDF (Typst, Graphviz) into a
/// `PDFView`, recompiling (debounced) as the buffer changes. Read-only preview;
/// editing happens in the Source view. Reuses `CompiledPreviewContainerView`.
struct CompiledPDFPreviewView: NSViewRepresentable {
    let content: String
    var isBufferLoading: Bool = false
    var documentURL: URL? = nil
    /// Format-specific compile step: source → (pdfURL, log).
    let compile: (String, URL?) async -> (URL?, String)

    static let debounce: TimeInterval = 0.5

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> CompiledPreviewContainerView {
        let container = CompiledPreviewContainerView()
        context.coordinator.attach(container: container)
        container.showStatus(AppStrings.LaTeX.compiling, isError: false)
        context.coordinator.scheduleCompile(force: true)
        return container
    }

    func updateNSView(_ container: CompiledPreviewContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scheduleCompile(force: false)
    }

    static func dismantleNSView(_ container: CompiledPreviewContainerView, coordinator: Coordinator) {
        coordinator.shutdown()
    }

    @MainActor
    final class Coordinator {
        var parent: CompiledPDFPreviewView
        private weak var container: CompiledPreviewContainerView?
        private var lastContent: String?
        private var pending: DispatchWorkItem?
        private var task: Task<Void, Never>?
        private var currentPDFURL: URL?

        init(parent: CompiledPDFPreviewView) { self.parent = parent }
        func attach(container: CompiledPreviewContainerView) { self.container = container }

        func scheduleCompile(force: Bool) {
            guard !parent.isBufferLoading else { return }
            guard force || parent.content != lastContent else { return }
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.compileNow() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + CompiledPDFPreviewView.debounce, execute: work)
        }

        private func compileNow() {
            let source = parent.content
            let documentURL = parent.documentURL
            lastContent = source
            container?.showStatus(AppStrings.LaTeX.compiling, isError: false)
            task?.cancel()
            task = Task { [weak self] in
                guard let self else { return }
                let (pdfURL, log) = await self.parent.compile(source, documentURL)
                if Task.isCancelled { return }
                if let pdfURL, let doc = PDFDocument(url: pdfURL) {
                    self.cleanup(keeping: pdfURL)
                    self.currentPDFURL = pdfURL
                    self.container?.display(document: doc)
                } else {
                    self.container?.showCompileError(log: log.split(separator: "\n").suffix(40).joined(separator: "\n"))
                }
            }
        }

        func shutdown() {
            pending?.cancel(); task?.cancel(); cleanup(keeping: nil)
        }

        private func cleanup(keeping newURL: URL?) {
            guard let old = currentPDFURL, old != newURL else { return }
            try? FileManager.default.removeItem(at: old.deletingLastPathComponent())
        }
    }
}

// MARK: - HTMLDocPreviewView (generic, read-only)

/// Renders any source that compiles to an HTML string (AsciiDoc) into a
/// `WKWebView`, recompiling (debounced) as the buffer changes.
struct HTMLDocPreviewView: NSViewRepresentable {
    let content: String
    var isBufferLoading: Bool = false
    var documentURL: URL? = nil
    /// Format-specific render step: source → (html, log).
    let render: (String, URL?) async -> (String?, String)

    static let debounce: TimeInterval = 0.5

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView: webView)
        context.coordinator.scheduleRender(force: true)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scheduleRender(force: false)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.shutdown()
    }

    @MainActor
    final class Coordinator {
        var parent: HTMLDocPreviewView
        private weak var webView: WKWebView?
        private var lastContent: String?
        private var pending: DispatchWorkItem?
        private var task: Task<Void, Never>?

        init(parent: HTMLDocPreviewView) { self.parent = parent }
        func attach(webView: WKWebView) { self.webView = webView }

        func scheduleRender(force: Bool) {
            guard !parent.isBufferLoading else { return }
            guard force || parent.content != lastContent else { return }
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.renderNow() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + HTMLDocPreviewView.debounce, execute: work)
        }

        private func renderNow() {
            let source = parent.content
            let documentURL = parent.documentURL
            lastContent = source
            task?.cancel()
            task = Task { [weak self] in
                guard let self else { return }
                let (html, log) = await self.parent.render(source, documentURL)
                if Task.isCancelled { return }
                let baseURL = documentURL?.deletingLastPathComponent()
                self.webView?.loadHTMLString(html ?? Self.errorHTML(log), baseURL: baseURL)
            }
        }

        func shutdown() { pending?.cancel(); task?.cancel() }

        private static func errorHTML(_ log: String) -> String {
            let escaped = log
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            return "<html><body style='font:13px -apple-system;color:#b00;padding:24px'>"
                + "<b>\(AppStrings.LaTeX.compileFailedTitle)</b><pre style='white-space:pre-wrap;color:#888'>\(escaped)</pre></body></html>"
        }
    }
}
