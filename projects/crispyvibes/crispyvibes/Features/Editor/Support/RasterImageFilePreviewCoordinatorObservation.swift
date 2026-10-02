import AppKit
import Foundation

/// File-system and scroll-bounds observation for the raster preview.
extension RasterImageFilePreviewCoordinator {
    func installBoundsObserverIfNeeded() {
        guard boundsObserver == nil, let clipView = scrollView?.contentView else { return }
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshCenteringInsets()
                self.reportZoom()
            }
        }
    }

    func configureFileObservation(for fileURL: URL) {
        guard observedPath != fileURL.path else { return }
        tearDownFileObservation()

        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reloadImageIfNeeded(from: fileURL, force: false)
                let events = source?.data ?? []
                if events.contains(.rename) || events.contains(.delete) || events.contains(.revoke) {
                    self.observedPath = nil
                    self.configureFileObservation(for: fileURL)
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }

        observedPath = fileURL.path
        fileObservationSource = source
        source.resume()
    }

    func tearDownFileObservation() {
        fileObservationSource?.cancel()
        fileObservationSource = nil
        observedPath = nil
    }
}
