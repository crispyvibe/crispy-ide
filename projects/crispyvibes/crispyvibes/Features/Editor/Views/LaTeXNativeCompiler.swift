import Foundation
import OSLog

/// Native, fully-offline LaTeX compiler built on a local TeX Live install
/// (BasicTeX / MacTeX). Runs `pdflatex -synctex=1` in a scratch directory and
/// returns the produced PDF, the SyncTeX data, and the log. Also exposes the
/// SyncTeX reverse map (a point on the rendered page → a source line), which is
/// what makes editing-on-the-rendered-page possible.
///
/// This replaces the abandoned WASM/remote-server path: the engine and all
/// packages live on disk, so compilation needs no network.
struct LaTeXNativeCompiler {
    struct CompileResult {
        let pdfURL: URL?
        let log: String
    }

    /// A resolved source location from a SyncTeX reverse lookup.
    struct SourceLocation: Equatable {
        let file: String
        let line: Int
    }

    enum CompileError: Error, LocalizedError {
        case toolchainMissing
        var errorDescription: String? {
            switch self {
            case .toolchainMissing:
                return "No LaTeX toolchain found. Install BasicTeX or MacTeX (expected at /Library/TeX/texbin)."
            }
        }
    }

    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "latex.native")

    /// Directories to search for `pdflatex` / `synctex`, best-first.
    private static let toolchainSearchPaths: [String] = [
        "/Library/TeX/texbin",
        "/usr/local/texlive/2026basic/bin/universal-darwin",
        "/usr/local/texlive/2025basic/bin/universal-darwin",
        "/opt/homebrew/bin",
        "/usr/local/bin"
    ]

    /// Whether a usable toolchain is present on this machine.
    static var isToolchainAvailable: Bool { toolURL(named: "pdflatex") != nil }

    /// Homebrew command to install a minimal TeX engine (shown in the
    /// toolchain-missing empty state).
    static let installCommand = "brew install --cask basictex"

    /// Resolve a TeX tool by name from the known install locations.
    static func toolURL(named tool: String) -> URL? {
        for dir in toolchainSearchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Compile `source` to a PDF. `documentURL` (if known) is added to
    /// `TEXINPUTS` so the document's own `\input`/`\includegraphics`/local
    /// classes resolve. Runs `pdflatex` multiple times (and `bibtex` when the
    /// document declares a bibliography) so cross-references and citations
    /// resolve — a single pass leaves `??`/`[?]` placeholders.
    func compile(source: String, documentURL: URL?) async throws -> CompileResult {
        guard let pdflatex = ExternalTool.resolve("pdflatex") else {
            throw CompileError.toolchainMissing
        }

        let fileManager = FileManager.default
        let buildDir = try ExternalTool.makeScratchDir()
        let mainTeX = buildDir.appendingPathComponent("main.tex")
        try source.data(using: .utf8)?.write(to: mainTeX)

        var texInputs = ".//:"
        if let docDir = documentURL?.deletingLastPathComponent().path {
            texInputs = "\(docDir)//:\(texInputs)"
        }
        let env = ["TEXINPUTS": texInputs]
        let args = [
            "-synctex=1",
            "-interaction=nonstopmode",
            "-output-directory=\(buildDir.path)",
            mainTeX.path
        ]

        // pdflatex writes its log to stdout; use it to decide whether to rerun.
        func runPass() async -> String {
            let out = await ExternalTool.run(pdflatex, args, cwd: buildDir, env: env)
            return String(data: out.stdout, encoding: .utf8) ?? ""
        }

        var log = await runPass()

        // External bibliography → run bibtex, then re-typeset.
        let usesBibTeX = source.contains("\\bibliography{") || source.contains("\\addbibresource")
        if usesBibTeX, let bibtex = ExternalTool.resolve("bibtex") {
            _ = await ExternalTool.run(bibtex, ["main"], cwd: buildDir, env: env)
            log = await runPass()
        }

        // Re-run until cross-references stabilize (cap the passes).
        var passes = 1
        while passes < 4, Self.needsRerun(log) {
            log = await runPass()
            passes += 1
        }

        let pdfURL = buildDir.appendingPathComponent("main.pdf")
        let hasPDF = fileManager.fileExists(atPath: pdfURL.path)
        // On failure there's no PDF to keep (and the dir won't be tracked by the
        // view for later cleanup), so remove it now to avoid leaking scratch dirs.
        if !hasPDF { try? fileManager.removeItem(at: buildDir) }
        return CompileResult(pdfURL: hasPDF ? pdfURL : nil, log: log)
    }

    /// Whether the pdflatex log asks for another pass.
    private static func needsRerun(_ log: String) -> Bool {
        log.contains("Rerun to get")
            || log.contains("Label(s) may have changed")
            || log.contains("Please rerun")
    }

    /// SyncTeX reverse map: a point on a rendered page → the source line that
    /// produced it. `page` is 1-based; `x`/`y` are in PDF points from the
    /// top-left of the page.
    func sourceLocation(forPDFAt pdfURL: URL, page: Int, x: Double, y: Double) async -> SourceLocation? {
        guard let synctex = Self.toolURL(named: "synctex") else { return nil }
        let out = await ExternalTool.run(
            synctex, ["edit", "-o", "\(page):\(x):\(y):\(pdfURL.path)"], cwd: nil, timeout: 10
        )
        var file: String?
        var line: Int?
        for raw in (String(data: out.stdout, encoding: .utf8) ?? "").split(separator: "\n") {
            if raw.hasPrefix("Input:") { file = String(raw.dropFirst("Input:".count)) }
            if raw.hasPrefix("Line:") { line = Int(raw.dropFirst("Line:".count).trimmingCharacters(in: .whitespaces)) }
        }
        if let file, let line { return SourceLocation(file: file, line: line) }
        return nil
    }

    /// One typeset box for a source line, in SyncTeX page coordinates
    /// (origin top-left, points). `page` is 1-based.
    struct SyncBox: Sendable {
        let page: Int
        let h: Double
        let v: Double
        let width: Double
        let height: Double
    }

    /// SyncTeX forward map: a source line → the box(es) it produced on the page.
    /// Used to highlight the region a click/edit affects. `mainTeXPath` must be
    /// the file path that was compiled (it appears in the .synctex data).
    func forwardBoxes(forLine line: Int, mainTeXPath: String, pdfURL: URL) async -> [SyncBox] {
        guard let synctex = Self.toolURL(named: "synctex") else { return [] }
        let out = await ExternalTool.run(
            synctex, ["view", "-i", "\(line):1:\(mainTeXPath)", "-o", pdfURL.path], cwd: nil, timeout: 10
        )
        let output = String(data: out.stdout, encoding: .utf8) ?? ""
        var boxes: [SyncBox] = []
        var page = 1, h = 0.0, v = 0.0, w = 0.0
        func value(_ s: Substring, _ prefix: String) -> Double {
            Double(s.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        for raw in output.split(separator: "\n") {
            let s = raw.trimmingCharacters(in: .whitespaces)[...]
            if s.hasPrefix("Page:") { page = Int(s.dropFirst(5)) ?? page }
            else if s.hasPrefix("h:") { h = value(s, "h:") }
            else if s.hasPrefix("v:") { v = value(s, "v:") }
            else if s.hasPrefix("W:") { w = value(s, "W:") }
            else if s.hasPrefix("H:") {
                boxes.append(SyncBox(page: page, h: h, v: v, width: w, height: value(s, "H:")))
            }
        }
        return boxes
    }
}
