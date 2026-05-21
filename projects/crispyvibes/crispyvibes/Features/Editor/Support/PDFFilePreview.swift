import Foundation
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct PDFFilePreview: NSViewRepresentable {
    let fileURL: URL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appThemePalette) private var appThemePalette

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        let theme = SyntaxTheme.fromPalette(appThemePalette, colorScheme: colorScheme)
        view.backgroundColor = theme.background
        view.document = PDFDocument(url: fileURL)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let theme = SyntaxTheme.fromPalette(appThemePalette, colorScheme: colorScheme)
        nsView.backgroundColor = theme.background
        if nsView.document?.documentURL != fileURL {
            nsView.document = PDFDocument(url: fileURL)
        }
    }
}

struct MarkdownImageCandidate {
    let filename: String
    let relativePath: String
    let insertPath: String
    let previewURL: String

    var scriptPayload: [String: String] {
        [
            "filename": filename,
            "relativePath": relativePath,
            "insertPath": insertPath,
            "previewURL": previewURL
        ]
    }
}
