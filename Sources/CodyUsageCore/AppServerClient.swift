import Foundation

public enum AppServerError: LocalizedError {
    case executableMissing, processFailed, timeout, invalidResponse, rpc(String)
    public var errorDescription: String? {
        switch self {
        case .executableMissing: "Codex 실행 파일을 찾지 못했습니다."
        case .processFailed: "Codex app-server를 시작하지 못했습니다."
        case .timeout: "Codex app-server 응답 시간이 초과되었습니다."
        case .invalidResponse: "Codex app-server 응답 형식이 호환되지 않습니다."
        case .rpc(let message): message
        }
    }
}

public final class AppServerClient: @unchecked Sendable {
    public typealias NotificationHandler = @Sendable (String, Data) -> Void

    private let queue = DispatchQueue(label: "CodyUsageOverlay.AppServer")
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextId = 0
    private var pending: [Int: (Result<Data, Error>) -> Void] = [:]
    private var initialized = false
    private var notificationHandler: NotificationHandler?

    public init() {}

    public func setNotificationHandler(_ handler: NotificationHandler?) {
        queue.async { self.notificationHandler = handler }
    }

    public func start() async throws {
        if queue.sync(execute: { initialized && process?.isRunning == true }) { return }
        try await stop()
        guard let executable = Self.locateExecutable() else { throw AppServerError.executableMissing }

        let newProcess = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        newProcess.executableURL = executable
        newProcess.arguments = ["app-server", "--stdio"]
        newProcess.standardInput = stdinPipe
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = stderrPipe
        newProcess.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        newProcess.terminationHandler = { [weak self] _ in self?.handleTermination() }
        do { try newProcess.run() } catch { throw AppServerError.processFailed }
        queue.sync { process = newProcess; input = stdinPipe.fileHandleForWriting }

        _ = try await call(
            method: "initialize",
            params: [
                "clientInfo": ["name": "cody-usage-overlay", "title": "Cody Usage Overlay", "version": "1.0.0"],
                "capabilities": ["experimentalApi": true],
            ],
            allowUninitialized: true
        )
        try sendNotification(method: "initialized", params: [:])
        queue.sync { initialized = true }
    }

    public func readRateLimits() async throws -> Data {
        try await start()
        return try await call(method: "account/rateLimits/read", params: [:])
    }

    public func stop() async throws {
        queue.sync {
            initialized = false
            input?.readabilityHandler = nil
            input = nil
            if let process, process.isRunning { process.terminate() }
            process = nil
            let callbacks = pending.values
            pending.removeAll()
            callbacks.forEach { $0(.failure(AppServerError.processFailed)) }
        }
    }

    public static func locateExecutable() -> URL? {
        let bundled = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in environmentPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func call(method: String, params: [String: Any], allowUninitialized: Bool = false) async throws -> Data {
        if !allowUninitialized && !queue.sync(execute: { initialized }) { throw AppServerError.processFailed }
        let id = queue.sync { nextId += 1; return nextId }
        var encoded = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        encoded.append(0x0A)
        let requestData = encoded
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.pending[id] = { continuation.resume(with: $0) }
                do {
                    try self.writeData(requestData)
                    self.queue.asyncAfter(deadline: .now() + 15) {
                        if let callback = self.pending.removeValue(forKey: id) { callback(.failure(AppServerError.timeout)) }
                    }
                } catch {
                    self.pending.removeValue(forKey: id)?(.failure(error))
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
        data.append(0x0A)
        try queue.sync { try writeData(data) }
    }

    private func writeData(_ data: Data) throws {
        guard let input else { throw AppServerError.processFailed }
        try input.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        queue.async {
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer[..<newline]
                self.buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if let id = (object["id"] as? NSNumber)?.intValue,
                   let callback = self.pending.removeValue(forKey: id) {
                    if let error = object["error"] as? [String: Any] {
                        callback(.failure(AppServerError.rpc(error["message"] as? String ?? "Codex RPC 오류")))
                    } else if let result = object["result"],
                              let resultData = try? JSONSerialization.data(withJSONObject: result) {
                        callback(.success(resultData))
                    } else {
                        callback(.failure(AppServerError.invalidResponse))
                    }
                } else if let method = object["method"] as? String {
                    let params = object["params"] ?? [:]
                    if let paramsData = try? JSONSerialization.data(withJSONObject: params) {
                        self.notificationHandler?(method, paramsData)
                    }
                }
            }
        }
    }

    private func handleTermination() {
        queue.async {
            self.initialized = false
            let callbacks = self.pending.values
            self.pending.removeAll()
            callbacks.forEach { $0(.failure(AppServerError.processFailed)) }
        }
    }
}
