import Foundation
import WebKit
import AppKit

final class BrowserDownloadDelegate: NSObject, WKDownloadDelegate {
    var onDownloadStarted: (() -> Void)?
    var onDownloadEnded: (() -> Void)?

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        onDownloadStarted?()
        let filename = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + filename)
        completionHandler(tempURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        onDownloadEnded?()
        guard let tempURL = download.progress.fileURL ?? findTempURL(for: download) else { return }
        let suggestedName = tempURL.lastPathComponent.components(separatedBy: "-").dropFirst().joined(separator: "-")
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedName.isEmpty ? tempURL.lastPathComponent : suggestedName
            panel.canCreateDirectories = true
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.begin { result in
                guard result == .OK, let dest = panel.url else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        onDownloadEnded?()
        NSLog("BrowserDownloadDelegate: download failed: %@", error.localizedDescription)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = AppStrings.Browser.downloadFailed
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: AppStrings.Common.ok)
            alert.runModal()
        }
    }

    private var tempURLs: [ObjectIdentifier: URL] = [:]

    private func findTempURL(for download: WKDownload) -> URL? {
        tempURLs.removeValue(forKey: ObjectIdentifier(download))
    }
}
