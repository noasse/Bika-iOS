import Foundation
import OSLog

nonisolated final class ImageDiagnosticSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var nextValue: UInt64
    private var lastIssuedValue: UInt64?

    init(startingAt value: UInt64) {
        nextValue = value
    }

    func take() -> UInt64 {
        lock.withLock {
            let value = nextValue
            defer { nextValue &+= 1 }
            lastIssuedValue = value
            return value
        }
    }

    func lastIssued() -> UInt64? {
        lock.withLock { lastIssuedValue }
    }
}

private actor ImageDiagnosticsPersistence {
    private struct ArrivalWaiter {
        let target: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private let fileURL: URL
    private let maximumEventCount: Int
    private var events: [ImageDiagnosticEvent]
    private var nextUnreceivedSequence: UInt64
    private var receivedSequences: Set<UInt64> = []
    private var arrivalWaiters: [ArrivalWaiter] = []
    private var persistenceGeneration: UInt64 = 0
    private var persistedGeneration: UInt64 = 0
    private var scheduledWriteTask: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.noasse.bika",
        category: "ImageDiagnosticsPersistence"
    )

    init(
        fileURL: URL,
        maximumEventCount: Int,
        initialEvents: [ImageDiagnosticEvent],
        firstLiveSequence: UInt64
    ) {
        self.fileURL = fileURL
        self.maximumEventCount = max(1, maximumEventCount)
        events = Array(initialEvents.suffix(max(1, maximumEventCount)))
        nextUnreceivedSequence = firstLiveSequence
    }

    func append(_ event: ImageDiagnosticEvent) {
        events.append(event)
        events.sort { $0.sequence < $1.sequence }
        if events.count > maximumEventCount {
            events.removeFirst(events.count - maximumEventCount)
        }
        persistenceGeneration &+= 1
        receivedSequences.insert(event.sequence)
        while receivedSequences.remove(nextUnreceivedSequence) != nil {
            nextUnreceivedSequence &+= 1
        }
        resumeSatisfiedArrivalWaiters()
        schedulePersistence()
    }

    func snapshot() -> [ImageDiagnosticEvent] {
        events.sorted { $0.sequence < $1.sequence }
    }

    func status() -> ImageDiagnosticsStatus {
        ImageDiagnosticsStatus(
            eventCount: events.count,
            lastErrorAt: events.last(where: { $0.action == .failed })?.timestamp
        )
    }

    func clear() throws {
        scheduledWriteTask?.cancel()
        scheduledWriteTask = nil
        try persistThrowing([])
        events.removeAll()
        persistenceGeneration &+= 1
        persistedGeneration = persistenceGeneration
    }

    func flush(through target: UInt64) async {
        if nextUnreceivedSequence <= target {
            await withCheckedContinuation {
                arrivalWaiters.append(ArrivalWaiter(target: target, continuation: $0))
            }
        }
        persistPending()
    }

    private func schedulePersistence() {
        guard scheduledWriteTask == nil else { return }
        scheduledWriteTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.persistPending()
        }
    }

    private func persistPending() {
        scheduledWriteTask?.cancel()
        scheduledWriteTask = nil
        guard persistedGeneration != persistenceGeneration else { return }
        do {
            try persistThrowing(events)
        } catch {
            logger.error(
                "image diagnostics persistence failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        persistedGeneration = persistenceGeneration
    }

    private func persistThrowing(_ value: [ImageDiagnosticEvent]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }

    private func resumeSatisfiedArrivalWaiters() {
        let satisfied = arrivalWaiters.filter { $0.target < nextUnreceivedSequence }
        arrivalWaiters.removeAll { $0.target < nextUnreceivedSequence }
        satisfied.forEach { $0.continuation.resume() }
    }
}

nonisolated final class ImageDiagnosticsService:
    @unchecked Sendable,
    ImageDiagnosticsManaging
{
    static let shared = ImageDiagnosticsService()

    private let persistence: ImageDiagnosticsPersistence
    private let sequence: ImageDiagnosticSequence
    private let exportDirectory: URL
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.noasse.bika",
        category: "ImageDiagnostics"
    )

    convenience init() {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        self.init(
            fileURL: caches
                .appendingPathComponent("ImageDiagnostics", isDirectory: true)
                .appendingPathComponent("events.json"),
            maximumEventCount: 2_000,
            exportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ImageDiagnosticsExports", isDirectory: true)
        )
    }

    init(fileURL: URL, maximumEventCount: Int, exportDirectory: URL) {
        let recovered = Self.loadAndRecover(fileURL: fileURL)
        let firstLiveSequence = (recovered.map(\.sequence).max() ?? 0) &+ 1
        persistence = ImageDiagnosticsPersistence(
            fileURL: fileURL,
            maximumEventCount: maximumEventCount,
            initialEvents: recovered,
            firstLiveSequence: firstLiveSequence
        )
        sequence = ImageDiagnosticSequence(startingAt: firstLiveSequence)
        self.exportDirectory = exportDirectory
    }

    func record(_ event: ImageDiagnosticEvent) {
        var sequenced = event
        sequenced.sequence = sequence.take()
        if sequenced.action == .failed {
            logger.error(
                "image failure request=\(sequenced.requestID.uuidString, privacy: .public) network=\(sequenced.networkRequestID?.uuidString ?? "none", privacy: .public) stage=\(sequenced.stage.rawValue, privacy: .public) url=\(sequenced.url.absoluteString, privacy: .public) code=\(sequenced.errorCode ?? 0, privacy: .public)"
            )
        }
        Task(priority: .utility) {
            await persistence.append(sequenced)
        }
    }

    func status() async -> ImageDiagnosticsStatus {
        await flush()
        return await persistence.status()
    }

    func snapshot() async -> [ImageDiagnosticEvent] {
        await flush()
        return await persistence.snapshot()
    }

    func flush() async {
        guard let target = sequence.lastIssued() else { return }
        await persistence.flush(through: target)
    }

    func clear() async throws {
        await flush()
        try await persistence.clear()
    }

    func export(metadata: ImageDiagnosticsMetadata) async throws -> URL {
        await flush()
        let events = await persistence.snapshot()
        let value = ImageDiagnosticsExport(
            schemaVersion: 1,
            exportedAt: metadata.exportedAt,
            app: ImageDiagnosticsAppMetadata(
                version: metadata.appVersion,
                buildNumber: metadata.buildNumber
            ),
            device: ImageDiagnosticsDeviceMetadata(
                model: metadata.deviceModel,
                systemName: metadata.systemName,
                systemVersion: metadata.systemVersion
            ),
            settings: ImageDiagnosticsSettingsMetadata(
                imageQuality: metadata.imageQuality
            ),
            summary: ImageDiagnosticsSummary(
                eventCount: events.count,
                firstEventAt: events.first?.timestamp,
                lastEventAt: events.last?.timestamp,
                succeededCount: events.filter { $0.action == .succeeded }.count,
                failureCount: events.filter { $0.action == .failed }.count,
                cancellationCount: events.filter { $0.action == .cancelled }.count,
                coverCount: events.filter { $0.purpose == .cover }.count,
                readerVisibleCount: events.filter { $0.purpose == .readerVisible }.count,
                readerPrefetchCount: events.filter { $0.purpose == .readerPrefetch }.count,
                unspecifiedCount: events.filter { $0.purpose == .unspecified }.count
            ),
            events: events
        )
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        try Self.removeOldExports(in: exportDirectory)
        let name = "bika-image-diagnostics-\(Self.fileTimestamp(metadata.exportedAt)).json"
        let url = exportDirectory.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        return url
    }

    private static func loadAndRecover(fileURL: URL) -> [ImageDiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(
                [ImageDiagnosticEvent].self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            let backup = fileURL
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(fileTimestamp(Date())).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return []
        }
    }

    private static func removeOldExports(in directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for file in files where file.lastPathComponent.hasPrefix(
            "bika-image-diagnostics-"
        ) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func fileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
