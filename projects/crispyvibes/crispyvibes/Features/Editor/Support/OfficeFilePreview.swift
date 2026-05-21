import Foundation
import Quartz
import SwiftUI

/// Read-only preview for Office documents (Word, PowerPoint, Excel) using
/// macOS Quick Look. See F045 (Office Document Preview).
///
/// Mirrors the structure of `PDFFilePreview` so Office tabs inherit standard
/// Content Viewer behaviors (preview/persistent tabs, splits, restore, retarget,
/// detached windows) via the editor plugin registry without custom logic.
struct OfficeFilePreview: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = fileURL as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        // Only swap the item when the URL actually changed to avoid
        // discarding an in-flight render.
        let currentURL = (nsView.previewItem as? NSURL) as URL?
        if currentURL != fileURL {
            nsView.previewItem = fileURL as NSURL
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        // Release the rendered document so Quick Look frees its buffers when
        // the tab is closed (per F045 cleanup-on-tab-close).
        nsView.previewItem = nil
        nsView.close()
    }
}
