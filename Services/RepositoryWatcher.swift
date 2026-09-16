import Foundation
import CoreServices

/// Sleduje změny v pracovním adresáři přes FSEvents a volá `onChange` s debounce.
final class RepositoryWatcher {
    private var stream: FSEventStreamRef?
    private let root: String
    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        root = url.standardizedFileURL.path
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: NSArray.self)
            let list = (0..<count).compactMap { cfPaths[$0] as? String }
            watcher.handle(paths: list)
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        pending?.cancel()
    }

    isolated deinit { stop() }

    private func handle(paths: [String]) {
        let relevant = paths.contains { path in
            guard let range = path.range(of: "/.git/") ?? (path.hasSuffix("/.git") ? path.range(of: "/.git") : nil) else {
                return true
            }
            // Uvnitř .git reagujeme jen na změnu HEAD, refs a indexu, ne na zámky a objekty.
            let inner = path[range.upperBound...]
            return inner == "HEAD" || inner.hasPrefix("refs/") || inner == "index" || inner == "MERGE_HEAD"
        }
        guard relevant else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in
            MainActor.assumeIsolated { onChange() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }
}
