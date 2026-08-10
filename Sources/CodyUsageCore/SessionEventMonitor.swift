import CoreServices
import Foundation

public final class SessionEventMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable ([String]) -> Void
    private final class CallbackBox: @unchecked Sendable {
        let handler: Handler
        init(handler: @escaping Handler) { self.handler = handler }
    }

    private let path: String
    private let queue = DispatchQueue(label: "CodyUsageOverlay.FSEvents")
    private var stream: FSEventStreamRef?
    private var retainedBox: Unmanaged<CallbackBox>?

    public init(path: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").path) {
        self.path = path
    }

    public func start(handler: @escaping Handler) {
        guard stream == nil else { return }
        let box = Unmanaged.passRetained(CallbackBox(handler: handler))
        var context = FSEventStreamContext(version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, pathsPointer, _, _ in
            guard let info else { return }
            let array = Unmanaged<CFArray>.fromOpaque(pathsPointer).takeUnretainedValue()
            let paths = array as? [String] ?? []
            Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().handler(Array(paths.prefix(count)))
        }
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { box.release(); return }
        retainedBox = box
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        retainedBox?.release(); retainedBox = nil
    }

    deinit { stop() }
}
