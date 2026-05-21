import Foundation

final class GitHeadWatcher {
    let watchedPath: String
    private var source: DispatchSourceFileSystemObject?
    private let onChange: () -> Void
    private let watchQueue = DispatchQueue(label: "com.crispyvibe.app.git-head-watcher", qos: .utility)

    init(path: String, onChange: @escaping () -> Void) {
        self.watchedPath = path
        self.onChange = onChange
        startWatching()
    }

    private func startWatching() {
        source?.cancel()
        source = nil

        let descriptor = open(watchedPath, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: watchQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            self.onChange()
            // Git replaces .git/HEAD via rename — the old fd is now stale.
            // Re-create the watcher to track the new inode.
            if event.contains(.rename) || event.contains(.delete) {
                self.watchQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.startWatching()
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func invalidate() {
        source?.cancel()
        source = nil
    }

    deinit { invalidate() }
}
