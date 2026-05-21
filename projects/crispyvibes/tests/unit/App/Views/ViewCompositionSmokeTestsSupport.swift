import AppKit
import Foundation
import PDFKit
import SwiftUI
import XCTest
@testable import CrispyVibes

@MainActor
extension ViewCompositionSmokeTests {
    func makeProjectSession(rootName: String) throws -> ProjectSession {
        let projectRoot = tempRoot.appendingPathComponent(rootName, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let layoutPersistence = LayoutPersistenceService(
            fileManager: .default,
            stateFileURL: layoutStateFileURL
        )
        return ProjectSession(
            rootURL: projectRoot,
            dependencies: makeProjectSessionDependencies(
                layoutPersistence: layoutPersistence
            )
        )
    }

    func makeProjectSessionDependencies(
        layoutPersistence: LayoutPersistenceService
    ) -> ProjectSessionDependencies {
        ProjectSessionDependencies(
            layoutPersistence: layoutPersistence,
            vibespaceManagement: vibespaceManagement,
            folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
            terminalViewModelFactory: container.makeTerminalViewModel,
            detachedWindowManager: container.detachedWindowManager
        )
    }

    func writeFixturePNG(to destinationURL: URL, size: NSSize) throws {
        let image = makeSolidImage(size: size, color: .systemTeal)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "ViewCompositionSmokeTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode fixture PNG data."]
            )
        }
        try pngData.write(to: destinationURL)
    }

    func writeFixturePDF(to destinationURL: URL) throws {
        let document = PDFDocument()
        guard let page = PDFPage(image: makeSolidImage(size: NSSize(width: 220, height: 140), color: .white)) else {
            throw NSError(
                domain: "ViewCompositionSmokeTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF page."]
            )
        }
        document.insert(page, at: 0)
        guard document.write(to: destinationURL) else {
            throw NSError(
                domain: "ViewCompositionSmokeTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write fixture PDF file."]
            )
        }
    }

    func makeSolidImage(size: NSSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    func binding<Value>(_ box: Box<Value>) -> Binding<Value> {
        Binding(
            get: { box.value },
            set: { box.value = $0 }
        )
    }

    func mount<V: View>(_ view: V) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
        hostingView.layoutSubtreeIfNeeded()
        _ = hostingView.fittingSize
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
