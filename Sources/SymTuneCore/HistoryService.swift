import Foundation

public final class HistoryService: @unchecked Sendable {
    private let dataDir: URL
    private let lock = NSLock()

    public init(dataDir: URL) {
        self.dataDir = dataDir
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }

    public func logEvent(_ event: HistoryEvent) {
        lock.lock()
        defer { lock.unlock() }

        let file = dataDir.appendingPathComponent("history.ndjson")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase

        guard let data = try? encoder.encode(event),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line += "\n"

        if FileManager.default.fileExists(atPath: file.path) {
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                } catch {
                    // Ignore errors to guarantee non-blocking behavior
                }
            }
        } else {
            do {
                try line.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                // Ignore errors
            }
        }
    }

    public func readEvents() -> [HistoryEvent] {
        lock.lock()
        defer { lock.unlock() }

        let file = dataDir.appendingPathComponent("history.ndjson")
        guard let data = try? Data(contentsOf: file),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { try? decoder.decode(HistoryEvent.self, from: Data($0.utf8)) }
    }
}
