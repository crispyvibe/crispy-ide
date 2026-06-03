import CoreServices
import Foundation

final class DirectoryWatcher {
    struct Event: Sendable {
        enum Kind: Int, Sendable {
            case modified = 0
            case created = 1
            case removed = 2
            case renamed = 3
            case rootChanged = 4
            case unknown = 5
        }

        let path: String
        let kind: Kind
        let isDirectory: Bool
        let rawFlags: FSEventStreamEventFlags
    }

    static let defaultMaxWatchedPaths = 256

    private static let eventCallback: FSEventStreamCallback = { _, info, eventCount, eventPathsPointer, eventFlagsPointer, _ in
        guard let info else { return }
        let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(eventPathsPointer, to: NSArray.self) as? [String] ?? []
        let eventFlags = UnsafeBufferPointer(
            start: eventFlagsPointer,
            count: Int(eventCount)
        )
        watcher.handleEvents(paths.prefix(Int(eventCount)), eventFlags: eventFlags)
    }

    private let queue = DispatchQueue(label: "com.crispyvibe.app.explorer.watcher", qos: .utility)
    private let maxWatchedPaths: Int
    private var onChange: ((String) -> Void)?
    private var onEvent: ((Event) -> Void)?
    private var activePaths: Set<String> = []
    private var stream: FSEventStreamRef?

    init(
        maxWatchedPaths: Int = DirectoryWatcher.defaultMaxWatchedPaths,
        onChange: ((String) -> Void)? = nil
    ) {
        self.maxWatchedPaths = max(1, maxWatchedPaths)
        self.onChange = onChange
    }

    func setOnChange(_ onChange: @escaping (String) -> Void) {
        self.onChange = onChange
    }

    func setOnEvent(_ onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    func updateWatchedPaths(_ paths: Set<String>) {
        let normalizedPaths = Self.cappedNormalizedPaths(
            from: paths,
            maxWatchedPaths: maxWatchedPaths
        )
        guard normalizedPaths != activePaths else { return }
        activePaths = normalizedPaths
        rebuildStream()
    }

    static func cappedNormalizedPaths(
        from paths: Set<String>,
        maxWatchedPaths: Int
    ) -> Set<String> {
        let normalizedPaths = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let cappedLimit = max(0, maxWatchedPaths)
        guard normalizedPaths.count > cappedLimit else {
            return normalizedPaths
        }

        let prioritized = normalizedPaths.sorted { lhs, rhs in
            let lhsDepth = lhs.split(separator: "/").count
            let rhsDepth = rhs.split(separator: "/").count
            if lhsDepth == rhsDepth {
                return lhs < rhs
            }
            return lhsDepth < rhsDepth
        }
        return Set(prioritized.prefix(cappedLimit))
    }

    func invalidate() {
        stopStream()
        activePaths.removeAll()
    }

    private func rebuildStream() {
        stopStream()

        let roots = Self.nonRedundantPaths(from: activePaths)
        guard !roots.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            roots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.15,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }

        self.stream = stream
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents<S: Sequence, F: Collection>(
        _ paths: S,
        eventFlags: F
    ) where S.Element == String, F.Element == FSEventStreamEventFlags {
        var eventsByPath: [String: Event] = [:]

        for (rawPath, flags) in zip(paths, eventFlags) {
            let normalizedPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            eventsByPath[normalizedPath] = Self.makeEvent(path: normalizedPath, flags: flags)
        }

        guard !eventsByPath.isEmpty else { return }

        for event in eventsByPath.values {
            onEvent?(event)
            onChange?(event.path)
        }
    }

    private static func makeEvent(path: String, flags: FSEventStreamEventFlags) -> Event {
        let kind: Event.Kind
        if hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)) {
            kind = .rootChanged
        } else if hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) {
            kind = .renamed
        } else if hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) {
            kind = .created
        } else if hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) {
            kind = .removed
        } else if hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified))
            || hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod))
            || hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod))
            || hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod))
            || hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner))
        {
            kind = .modified
        } else {
            kind = .unknown
        }

        return Event(
            path: path,
            kind: kind,
            isDirectory: hasFlag(flags, FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)),
            rawFlags: flags
        )
    }

    private static func hasFlag(
        _ flags: FSEventStreamEventFlags,
        _ flag: FSEventStreamEventFlags
    ) -> Bool {
        flags & flag != 0
    }

    private static func nonRedundantPaths(from paths: Set<String>) -> [String] {
        let sortedPaths = paths.sorted { lhs, rhs in
            let lhsDepth = lhs.split(separator: "/").count
            let rhsDepth = rhs.split(separator: "/").count
            if lhsDepth == rhsDepth {
                return lhs < rhs
            }
            return lhsDepth < rhsDepth
        }

        var roots: [String] = []
        for path in sortedPaths {
            if roots.contains(where: { containsPath($0, candidatePath: path) }) {
                continue
            }
            roots.append(path)
        }
        return roots
    }

    private static func containsPath(_ rootPath: String, candidatePath: String) -> Bool {
        if rootPath == candidatePath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    deinit {
        invalidate()
    }
}

/// Lifecycle/event interface for a filesystem watcher. Lets `ProjectSession`
/// own watching behind an abstraction (per DI guidelines) and lets tests inject
/// a spy in place of the concrete FSEvents-backed `DirectoryWatcher`.
protocol FileSystemEventWatching: AnyObject {
    func setOnEvent(_ onEvent: @escaping (DirectoryWatcher.Event) -> Void)
    func updateWatchedPaths(_ paths: Set<String>)
    func invalidate()
}

extension DirectoryWatcher: FileSystemEventWatching {}
