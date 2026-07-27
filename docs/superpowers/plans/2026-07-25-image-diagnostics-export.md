# Image Diagnostics Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a default-on, persistent, 2,000-event image-pipeline diagnostic log that records complete image URLs and can be exported as a privacy-warned JSON file from iOS Settings.

**Architecture:** Add a focused diagnostics model/service that assigns stable sequence numbers synchronously and persists snapshots through a serialized actor. Pass a lightweight diagnostic context through cover, visible-reader, prefetch, cache, coalescing, network, decode, and display boundaries. Export an immutable snapshot through `SettingsViewModel`, then present the resulting file with a UIKit activity controller bridged narrowly into SwiftUI.

**Tech Stack:** Swift 6, Swift Concurrency actors, Foundation `Codable`, atomic `Data.write`, OSLog, SwiftUI, UIKit `UIActivityViewController`, XCTest, XcodeBuildMCP.

## Global Constraints

- Persistence, settings UI, and export are iOS only. `ImageDataLoader.swift` is also compiled by the macOS target, so add only the pure event/protocol model `ImageDiagnostics.swift` to the manually maintained “Bika Shared” group and macOS Sources phase; macOS uses the no-op recorder and gets no logging feature.
- The `bika`, `bikaTests`, and `bikaUITests` targets use file-system-synchronized groups, so all other new files under those directories are discovered automatically. Edit `bika.xcodeproj/project.pbxproj` only for the one shared core-model reference described in Task 1.
- Preserve every pre-existing worktree change. Never use `git reset`, `git checkout --`, or a broad restore.
- The working tree already contains paused reader-toolbar, viewport, and image-recovery changes. Before each commit, stage only the exact files listed by that task and inspect `git diff --cached --name-only`.
- Full image URLs are intentionally recorded. Never record Authorization, Cookie, bearer tokens, passwords, arbitrary header dictionaries, API response bodies, or image bytes.
- Diagnostics are default-on and retain exactly the newest 2,000 events.
- Diagnostic recording and persistence failures must never change an image request, decode, cache, cancellation, or display result.
- Do not change `ReaderVerticalImageLayout`, its aspect-ratio source, or the wait-for-fit-width behavior.
- Do not add a third-party package.
- Follow strict TDD: add one failing behavior test, run it and observe the expected failure, then write the smallest implementation.

## File Map

- Create `bika/Support/ImageDiagnostics.swift`: event enums, context, event, status, export schema, and public protocols.
- Create `bika/Support/ImageDiagnosticsStore.swift`: bounded persistent store, sequence generator, OSLog mirroring, snapshot export, corruption recovery, and temporary-file cleanup.
- Modify `bika.xcodeproj/project.pbxproj`: compile only the pure diagnostics model in the shared macOS loader target.
- Modify `bika/bikaApp.swift`: flush the current diagnostics batch when the app leaves the active state.
- Create `bika/Views/Helpers/ActivityShareSheet.swift`: narrow `UIActivityViewController` bridge and identifiable export item.
- Create `bikaTests/ImageDiagnosticsTests.swift`: persistence, retention, corruption, export, privacy, and non-blocking failure tests.
- Modify `bika/Support/ImageDataLoader.swift`: report response-cache, coalescing, HTTP, retry, error, and cancellation events.
- Modify `bika/Support/ImageCache.swift`: report decoded-cache, decode, invalidation, retry, and cancellation events.
- Modify `bika/Views/Helpers/CachedAsyncImage.swift`: create cover/unspecified contexts and report display results.
- Modify `bika/Views/Helpers/MediaImageView.swift`: mark media thumbnails as `.cover`.
- Modify `bika/Views/Helpers/ZoomableImageView.swift`: accept a diagnostic context and report reader display/cancellation.
- Modify `bika/Views/ComicReaderView.swift`: mark visible and prefetch requests with stable purposes.
- Modify `bika/ViewModels/SettingsViewModel.swift`: expose status, clear, export, and localized messages.
- Modify `bika/Views/SettingsView.swift`: diagnostics section, privacy confirmation, export share sheet, and clear confirmation.
- Modify `bikaTests/ImagePipelineTests.swift`: coalescing correlation and network/cache/decode timeline assertions.
- Modify `bikaTests/CachedAsyncImageTests.swift`: cover purpose and display-event assertions.
- Modify `bikaTests/SettingsViewModelTests.swift`: status, export, and clear behavior.
- Modify `bikaUITests/BikaSmokeUITests.swift`: settings diagnostics controls and privacy confirmation smoke coverage.

---

### Task 0: Preserve the Two Existing Verified Fixes as Separate Checkpoints

**Files:**
- Existing toolbar fix:
  - `bika/Views/ComicReaderView.swift`
  - `bika/Support/ReaderViewportUpdate.swift`
  - `bikaTests/ReaderViewModelTests.swift`
  - `bikaUITests/BikaSmokeUITests.swift`
- Existing image-recovery fix:
  - `bika/Support/ImageDataLoader.swift`
  - `bika/Support/ImageCache.swift`
  - `bikaTests/ImagePipelineTests.swift`

**Interfaces:** No new interface is designed in this task. It checkpoints the already-reviewed viewport helper and the already-tested response validation/retry/decode-recovery changes before diagnostics modifies the same files.

- [ ] **Step 1: Re-run the existing focused unit regressions**

Run:

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaTests/ReaderViewModelTests",
    "-only-testing:bikaTests/ImagePipelineTests"
  ],
  "progress": true
})
```

Expected: all selected tests pass. The user has already manually verified the toolbar interaction; this step verifies viewport, true-height, cache, retry, decode, and cancellation behavior without changing source.

- [ ] **Step 2: Commit only the viewport/toolbar fix**

```bash
git add bika/Views/ComicReaderView.swift \
        bika/Support/ReaderViewportUpdate.swift \
        bikaTests/ReaderViewModelTests.swift \
        bikaUITests/BikaSmokeUITests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "fix: keep reader toolbar responsive after initial layout"
```

Expected staged names: exactly the four paths above. The commit includes the focused UI regression that already exists in `BikaSmokeUITests.swift`.

- [ ] **Step 3: Commit only the image-recovery fix**

```bash
git add bika/Support/ImageDataLoader.swift \
        bika/Support/ImageCache.swift \
        bikaTests/ImagePipelineTests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "fix: recover invalid and transient image responses"
```

Expected staged names: exactly the three paths above. Confirm the cached diff contains response validation, transient retries, decode-cache invalidation, and their tests—no diagnostics code yet.

---

### Task 1: Define the Event Model and Persistent Bounded Store

**Files:**
- Create: `bika/Support/ImageDiagnostics.swift`
- Create: `bika/Support/ImageDiagnosticsStore.swift`
- Modify: `bika.xcodeproj/project.pbxproj`
- Modify: `bika/bikaApp.swift`
- Create: `bikaTests/ImageDiagnosticsTests.swift`

**Interfaces:**
- Produces:
  - `ImageDiagnosticPurpose`
  - `ImageDiagnosticStage`
  - `ImageDiagnosticAction`
  - `ImageDiagnosticContext`
  - `ImageDiagnosticEvent`
  - `ImageDiagnosticsStatus`
  - `ImageDiagnosticsExport`
  - `ImageDiagnosticsRecording.record(_:)`
  - `ImageDiagnosticsManaging.status()`, `clear()`, and `export(metadata:)`
  - `ImageDiagnosticsService.shared`
- Consumes: Foundation, OSLog, and an injected file URL for tests.

- [ ] **Step 1: Write failing retention, persistence, corruption, export, and privacy tests**

Create `bikaTests/ImageDiagnosticsTests.swift` with these concrete tests and helpers:

```swift
import XCTest
@testable import bika

final class ImageDiagnosticsTests: XCTestCase {
    func testStoreKeepsNewestTwoThousandEventsAcrossRecreation() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("image-diagnostics.json")
        let first = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )

        for index in 0..<2_005 {
            first.record(makeEvent(urlSuffix: "\(index)"))
        }
        await first.flush()

        let recreated = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        let snapshot = await recreated.snapshot()

        XCTAssertEqual(snapshot.count, 2_000)
        XCTAssertTrue(snapshot.first?.url.absoluteString.hasSuffix("/5.jpg") == true)
        XCTAssertTrue(snapshot.last?.url.absoluteString.hasSuffix("/2004.jpg") == true)
        XCTAssertEqual(snapshot.map(\.sequence), snapshot.map(\.sequence).sorted())
    }

    func testCorruptStoreIsBackedUpAndRecordingContinues() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("image-diagnostics.json")
        try Data("not-json".utf8).write(to: fileURL)

        let service = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        service.record(makeEvent(urlSuffix: "after-corruption"))
        await service.flush()

        let status = await service.status()
        XCTAssertEqual(status.eventCount, 1)
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testExportIsStableJSONSnapshotWithoutCredentials() async throws {
        let directory = try makeTemporaryDirectory()
        let service = ImageDiagnosticsService(
            fileURL: directory.appendingPathComponent("events.json"),
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        let unsafeError = NSError(
            domain: "ImageTest",
            code: 401,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Authorization: Bearer unit-test-token; Cookie=unit-test-cookie password=unit-test-password"
            ]
        )
        service.record(makeEvent(urlSuffix: "page?quality=original", error: unsafeError))
        await service.flush()

        let exportURL = try await service.export(metadata: .fixture)
        let data = try Data(contentsOf: exportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ImageDiagnosticsExport.self, from: data)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.app.version, "1.2.1")
        XCTAssertEqual(decoded.device.model, "iPhone-Test")
        XCTAssertEqual(decoded.settings.imageQuality, "original")
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertTrue(text.contains("quality=original"))
        XCTAssertTrue(text.contains("Authorization=<redacted>"))
        XCTAssertFalse(text.contains("unit-test-token"))
        XCTAssertFalse(text.contains("unit-test-cookie"))
        XCTAssertFalse(text.contains("unit-test-password"))
        XCTAssertFalse(text.contains("Authorization=unit"))
        XCTAssertFalse(text.contains("Cookie=unit"))
        XCTAssertFalse(text.contains("password=unit"))
    }

    func testPersistenceFailureDoesNotThrowFromRecord() async {
        let service = ImageDiagnosticsService(
            fileURL: URL(fileURLWithPath: "/dev/null/not-writable.json"),
            maximumEventCount: 2_000,
            exportDirectory: FileManager.default.temporaryDirectory
        )

        service.record(makeEvent(urlSuffix: "still-return-immediately"))
        await service.flush()

        let status = await service.status()
        XCTAssertEqual(status.eventCount, 1)
    }

    func testClearUpdatesMemoryAndPersistedFile() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("events.json")
        let service = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        service.record(makeEvent(urlSuffix: "before-clear"))
        try await service.clear()

        let clearedStatus = await service.status()
        XCTAssertEqual(clearedStatus.eventCount, 0)
        let recreated = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        let recreatedSnapshot = await recreated.snapshot()
        XCTAssertTrue(recreatedSnapshot.isEmpty)
    }

    func testCompletedExportDoesNotChangeWhenLaterEventIsRecorded() async throws {
        let directory = try makeTemporaryDirectory()
        let service = ImageDiagnosticsService(
            fileURL: directory.appendingPathComponent("events.json"),
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        service.record(makeEvent(urlSuffix: "included"))
        let exportURL = try await service.export(metadata: .fixture)
        let exportedData = try Data(contentsOf: exportURL)

        service.record(makeEvent(urlSuffix: "later"))
        await service.flush()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            ImageDiagnosticsExport.self,
            from: exportedData
        )
        XCTAssertEqual(decoded.events.map(\.url.lastPathComponent), ["included.jpg"])
        let status = await service.status()
        XCTAssertEqual(status.eventCount, 2)
    }

    private func makeEvent(urlSuffix: String, error: Error? = nil) -> ImageDiagnosticEvent {
        return ImageDiagnosticEvent(
            sequence: 0,
            timestamp: Date(),
            requestID: UUID(),
            networkRequestID: nil,
            purpose: .readerVisible,
            stage: .load,
            action: .started,
            url: URL(string: "https://images.bika.test/\(urlSuffix).jpg")!,
            cacheIdentity: nil,
            httpStatus: nil,
            responseBytes: nil,
            durationMilliseconds: nil,
            retryAttempt: 0,
            decodeTarget: nil,
            sourcePixelSize: nil,
            decodedPixelSize: nil,
            error: error,
            metadata: ImageDiagnosticEventMetadata(
                pageStableID: "page-\(urlSuffix)",
                contentType: nil,
                wasCachedResponse: nil
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private extension ImageDiagnosticsMetadata {
    static let fixture = ImageDiagnosticsMetadata(
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
        appVersion: "1.2.1",
        buildNumber: "42",
        deviceModel: "iPhone-Test",
        systemName: "iOS",
        systemVersion: "26.5",
        imageQuality: "original"
    )
}
```

- [ ] **Step 2: Run the new test file and verify it fails for missing types**

Run with XcodeBuildMCP:

```text
test_sim({
  "extraArgs": ["-only-testing:bikaTests/ImageDiagnosticsTests"],
  "progress": true
})
```

Expected: build failure naming `ImageDiagnosticsService` or `ImageDiagnosticEvent` as missing.

- [ ] **Step 3: Implement exact model and protocol surface**

Create `bika/Support/ImageDiagnostics.swift`:

```swift
import CoreGraphics
import Foundation

nonisolated enum ImageDiagnosticPurpose: String, Codable, Sendable {
    case cover
    case readerVisible
    case readerPrefetch
    case unspecified
}

nonisolated enum ImageDiagnosticStage: String, Codable, Sendable {
    case load
    case decodedCache
    case responseCache
    case coalescing
    case network
    case decode
    case display
}

nonisolated enum ImageDiagnosticAction: String, Codable, Sendable {
    case started
    case hit
    case missed
    case joined
    case response
    case retrying
    case evicted
    case succeeded
    case failed
    case cancelled
}

nonisolated struct ImageDiagnosticSize: Codable, Equatable, Sendable {
    let width: Double
    let height: Double

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }
}

nonisolated struct ImageDiagnosticContext: Equatable, Sendable {
    let requestID: UUID
    let purpose: ImageDiagnosticPurpose
    let url: URL
    let pageStableID: String?

    init(
        requestID: UUID = UUID(),
        purpose: ImageDiagnosticPurpose,
        url: URL,
        pageStableID: String? = nil
    ) {
        self.requestID = requestID
        self.purpose = purpose
        self.url = url
        self.pageStableID = pageStableID
    }
}

nonisolated struct ImageDiagnosticEventMetadata: Codable, Equatable, Sendable {
    let pageStableID: String?
    let contentType: String?
    let wasCachedResponse: Bool?
}

nonisolated struct ImageDiagnosticEvent: Codable, Equatable, Sendable {
    var sequence: UInt64
    let timestamp: Date
    let requestID: UUID
    let networkRequestID: UUID?
    let purpose: ImageDiagnosticPurpose
    let stage: ImageDiagnosticStage
    let action: ImageDiagnosticAction
    let url: URL
    let cacheIdentity: String?
    let httpStatus: Int?
    let responseBytes: Int?
    let durationMilliseconds: Double?
    let retryAttempt: Int
    let decodeTarget: String?
    let sourcePixelSize: ImageDiagnosticSize?
    let decodedPixelSize: ImageDiagnosticSize?
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
    let metadata: ImageDiagnosticEventMetadata

    init(
        sequence: UInt64,
        timestamp: Date,
        requestID: UUID,
        networkRequestID: UUID?,
        purpose: ImageDiagnosticPurpose,
        stage: ImageDiagnosticStage,
        action: ImageDiagnosticAction,
        url: URL,
        cacheIdentity: String?,
        httpStatus: Int?,
        responseBytes: Int?,
        durationMilliseconds: Double?,
        retryAttempt: Int,
        decodeTarget: String?,
        sourcePixelSize: ImageDiagnosticSize?,
        decodedPixelSize: ImageDiagnosticSize?,
        error: Error?,
        metadata: ImageDiagnosticEventMetadata
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.requestID = requestID
        self.networkRequestID = networkRequestID
        self.purpose = purpose
        self.stage = stage
        self.action = action
        self.url = url
        self.cacheIdentity = cacheIdentity
        self.httpStatus = httpStatus
        self.responseBytes = responseBytes
        self.durationMilliseconds = durationMilliseconds
        self.retryAttempt = retryAttempt
        self.decodeTarget = decodeTarget
        self.sourcePixelSize = sourcePixelSize
        self.decodedPixelSize = decodedPixelSize
        let safeError = error.map(Self.safeErrorFields)
        errorDomain = safeError?.domain
        errorCode = safeError?.code
        errorDescription = safeError?.description
        self.metadata = metadata
    }

    private static func safeErrorFields(
        _ error: Error
    ) -> (domain: String, code: Int, description: String) {
        let nsError = error as NSError
        let description = nsError.localizedDescription
            .replacingOccurrences(
                of: #"(?i)\b(authorization|cookie|password)\b\s*[:=]\s*(?:bearer\s+)?[^,;\s]+"#,
                with: "$1=<redacted>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#,
                with: "Bearer <redacted>",
                options: .regularExpression
            )
        return (
            nsError.domain,
            nsError.code,
            description
        )
    }
}

nonisolated struct ImageDiagnosticsStatus: Equatable, Sendable {
    let eventCount: Int
    let lastErrorAt: Date?
}

nonisolated struct ImageDiagnosticsMetadata: Codable, Equatable, Sendable {
    let exportedAt: Date
    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let systemName: String
    let systemVersion: String
    let imageQuality: String
}

nonisolated struct ImageDiagnosticsSummary: Codable, Equatable, Sendable {
    let eventCount: Int
    let firstEventAt: Date?
    let lastEventAt: Date?
    let succeededCount: Int
    let failureCount: Int
    let cancellationCount: Int
    let coverCount: Int
    let readerVisibleCount: Int
    let readerPrefetchCount: Int
    let unspecifiedCount: Int
}

nonisolated struct ImageDiagnosticsAppMetadata: Codable, Equatable, Sendable {
    let version: String
    let buildNumber: String
}

nonisolated struct ImageDiagnosticsDeviceMetadata: Codable, Equatable, Sendable {
    let model: String
    let systemName: String
    let systemVersion: String
}

nonisolated struct ImageDiagnosticsSettingsMetadata: Codable, Equatable, Sendable {
    let imageQuality: String
}

nonisolated struct ImageDiagnosticsExport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let app: ImageDiagnosticsAppMetadata
    let device: ImageDiagnosticsDeviceMetadata
    let settings: ImageDiagnosticsSettingsMetadata
    let summary: ImageDiagnosticsSummary
    let events: [ImageDiagnosticEvent]
}

nonisolated protocol ImageDiagnosticsRecording: Sendable {
    func record(_ event: ImageDiagnosticEvent)
}

nonisolated protocol ImageDiagnosticsManaging: ImageDiagnosticsRecording {
    func status() async -> ImageDiagnosticsStatus
    func snapshot() async -> [ImageDiagnosticEvent]
    func flush() async
    func clear() async throws
    func export(metadata: ImageDiagnosticsMetadata) async throws -> URL
}

nonisolated final class ImageDiagnosticsNoopRecorder:
    @unchecked Sendable,
    ImageDiagnosticsRecording
{
    static let shared = ImageDiagnosticsNoopRecorder()
    private init() {}
    func record(_ event: ImageDiagnosticEvent) {}
}
```

Because `ImageDataLoader.swift` is in the macOS Sources phase, add the core model to `bika.xcodeproj/project.pbxproj` with these unused stable IDs:

```text
EC88C0142FEA4000004AFB7B /* ImageDiagnostics.swift */
EC88D0142FEA4000004AFB7B /* ImageDiagnostics.swift in Sources */
```

Add one `PBXFileReference` pointing to `bika/Support/ImageDiagnostics.swift`, one `PBXBuildFile`, one child under `EC88C1002FEA4000004AFB7B /* Bika Shared */`, and one entry under `EC88BE432FEA2C25004AFB7B /* Sources */`. Do not add `ImageDiagnosticsStore.swift`, settings code, UIKit helpers, or iOS tests to the macOS target. Run `plutil -lint bika.xcodeproj/project.pbxproj` immediately after the edit.

- [ ] **Step 4: Implement the bounded store and service**

Create `bika/Support/ImageDiagnosticsStore.swift` with this behavior:

```swift
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

nonisolated final class ImageDiagnosticsService: @unchecked Sendable, ImageDiagnosticsManaging {
    static let shared = ImageDiagnosticsService()

    private let persistence: ImageDiagnosticsPersistence
    private let sequence: ImageDiagnosticSequence
    private let exportDirectory: URL
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.noasse.bika",
        category: "ImageDiagnostics"
    )

    convenience init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
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
        Task(priority: .utility) { await persistence.append(sequenced) }
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
        let events = await snapshot()
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
        for file in files where file.lastPathComponent.hasPrefix("bika-image-diagnostics-") {
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
```

`record(_:)` reserves the sequence synchronously before scheduling the actor append. `flush()` captures the newest reserved sequence, waits until every contiguous sequence through that value has reached the actor, then forces the current batch to make one persistence attempt. Normal traffic is coalesced into at most one atomic rewrite per 250 ms, so out-of-order tasks cannot make export return early and high-frequency image events do not rewrite the whole 2,000-event file one time per event.

In `bika/bikaApp.swift`, observe `scenePhase` and flush without blocking UI whenever the app is no longer active:

```swift
@Environment(\.scenePhase) private var scenePhase

// Apply to ContentView:
.onChange(of: scenePhase) { _, newPhase in
    guard newPhase != .active else { return }
    Task { await ImageDiagnosticsService.shared.flush() }
}
```

- [ ] **Step 5: Run tests and commit only the new diagnostics files**

Run:

```text
test_sim({
  "extraArgs": ["-only-testing:bikaTests/ImageDiagnosticsTests"],
  "progress": true
})
```

Expected: all `ImageDiagnosticsTests` pass with zero warnings.

Then:

```bash
git add bika/Support/ImageDiagnostics.swift \
        bika/Support/ImageDiagnosticsStore.swift \
        bika.xcodeproj/project.pbxproj \
        bika/bikaApp.swift \
        bikaTests/ImageDiagnosticsTests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "feat: add persistent image diagnostics store"
```

Expected staged names: exactly the five paths above.

---

### Task 2: Expose Coalescing IDs and Instrument Network, Cache, and Decode

**Files:**
- Modify: `bika/Support/ImageDataLoader.swift`
- Modify: `bika/Support/ImageCache.swift`
- Modify: `bikaTests/ImagePipelineTests.swift`

**Interfaces:**
- Consumes: `ImageDiagnosticContext`, `ImageDiagnosticsRecording`, and `ImageDiagnosticsService.shared`.
- Produces:
  - `CoalescingTaskRegistration(operationID:joinedExistingOperation:)`
  - overloaded `CoalescingTaskRegistry.value(for:onRegistration:operation:)`
  - `ImageDataLoadResult(data:networkRequestID:)`
  - `ImageDataLoading.loadResult(from:diagnosticContext:)`
  - `ImageDataLoading.invalidateCachedData(for:diagnosticContext:)`
  - `ImageCache.loadAsset(..., diagnosticContext:)`

- [ ] **Step 1: Write failing correlation and timeline tests**

Append these tests to `bikaTests/ImagePipelineTests.swift`:

```swift
func testCoalescingRegistryReportsSharedOperationIDToBothWaiters() async throws {
    let registry = CoalescingTaskRegistry<String, Int>()
    let registrations = LockedValue<[CoalescingTaskRegistration]>([])
    let operationStarts = LockedValue(0)
    let gate = TestAsyncGate()

    async let first = registry.value(
        for: "same",
        onRegistration: { registration in
            registrations.value.append(registration)
        },
        operation: { operationID in
            operationStarts.value += 1
            await gate.wait()
            return operationID.hashValue
        }
    )
    async let second = registry.value(
        for: "same",
        onRegistration: { registration in
            registrations.value.append(registration)
        },
        operation: { operationID in
            operationStarts.value += 1
            await gate.wait()
            return operationID.hashValue
        }
    )

    await waitUntilAsync { registrations.value.count == 2 }
    await gate.open()
    _ = try await [first, second]

    XCTAssertEqual(Set(registrations.value.map(\.operationID)).count, 1)
    XCTAssertEqual(registrations.value.filter(\.joinedExistingOperation).count, 1)
    XCTAssertEqual(operationStarts.value, 1)
}

func testImagePipelineRecordsCacheNetworkRetryDecodeAndSuccessTimeline() async throws {
    let diagnostics = RecordingImageDiagnostics()
    let validImageData = try makeJPEGData(
        size: CGSize(width: 40, height: 80),
        orientation: .up
    )
    let requestCount = LockedValue(0)
    let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    configuration.urlCache = responseCache
    MockURLProtocol.requestHandler = { _ in
        requestCount.value += 1
        if requestCount.value == 1 {
            return MockHTTPResponse(
                statusCode: 503,
                headers: ["Content-Type": "text/plain"],
                data: Data("retry".utf8)
            )
        }
        return MockHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/jpeg"],
            data: validImageData
        )
    }
    let loader = URLSessionImageDataLoader(
        session: URLSession(configuration: configuration),
        responseCache: responseCache,
        diagnostics: diagnostics,
        retryDelays: [.zero]
    )
    let cache = ImageCache(
        countLimit: 10,
        totalCostLimit: 1_024 * 1_024,
        diagnostics: diagnostics
    )
    let url = URL(string: "https://images.bika.test/timeline.jpg")!
    let context = ImageDiagnosticContext(purpose: .readerVisible, url: url)

    _ = try await cache.loadAsset(
        for: url,
        target: .fitWidth(100),
        imageLoader: loader,
        diagnosticContext: context
    )

    let events = diagnostics.events
    XCTAssertTrue(events.contains { $0.stage == .decodedCache && $0.action == .missed })
    XCTAssertTrue(events.contains { $0.stage == .network && $0.httpStatus == 503 })
    XCTAssertTrue(events.contains { $0.stage == .network && $0.action == .retrying })
    XCTAssertTrue(events.contains { $0.stage == .decode && $0.action == .succeeded })
    XCTAssertEqual(Set(events.map(\.requestID)), [context.requestID])
}

func testCoalescedImageCacheCallersReceiveSameActualNetworkRequestID() async throws {
    let diagnostics = RecordingImageDiagnostics()
    let data = try makeJPEGData(
        size: CGSize(width: 40, height: 80),
        orientation: .up
    )
    let url = URL(string: "https://images.bika.test/shared-network-id.jpg")!
    let firstContext = ImageDiagnosticContext(purpose: .readerVisible, url: url)
    let secondContext = ImageDiagnosticContext(purpose: .readerPrefetch, url: url)
    let gate = TestAsyncGate()
    let loader = GatedImageDataLoader(data: data, gate: gate)
    let cache = ImageCache(
        countLimit: 10,
        totalCostLimit: 1_024 * 1_024,
        diagnostics: diagnostics
    )

    async let first = cache.loadAsset(
        for: url,
        target: .fitWidth(100),
        imageLoader: loader,
        diagnosticContext: firstContext
    )
    async let second = cache.loadAsset(
        for: url,
        target: .fitWidth(100),
        imageLoader: loader,
        diagnosticContext: secondContext
    )
    await waitUntilAsync {
        diagnostics.events.contains {
            $0.stage == .coalescing && $0.action == .joined
        }
    }
    await gate.open()
    _ = try await [first, second]

    let callerIDs = [firstContext.requestID, secondContext.requestID]
    let completions = diagnostics.events.filter {
        callerIDs.contains($0.requestID)
            && $0.stage == .load
            && $0.action == .succeeded
    }
    XCTAssertEqual(Set(completions.map(\.requestID)), Set(callerIDs))
    XCTAssertEqual(Set(completions.compactMap(\.networkRequestID)).count, 1)
}

func testDiagnosticsPersistenceFailureDoesNotChangeImagePipelineResult() async throws {
    let diagnostics = ImageDiagnosticsService(
        fileURL: URL(fileURLWithPath: "/dev/null/not-writable.json"),
        maximumEventCount: 2_000,
        exportDirectory: FileManager.default.temporaryDirectory
    )
    let data = try makeJPEGData(
        size: CGSize(width: 40, height: 80),
        orientation: .up
    )
    let url = URL(string: "https://images.bika.test/persistence-failure.jpg")!
    let loader = CountingImageDataLoader(data: data)
    let cache = ImageCache(
        countLimit: 10,
        totalCostLimit: 1_024 * 1_024,
        diagnostics: diagnostics
    )

    let asset = try await cache.loadAsset(
        for: url,
        target: .fitWidth(100),
        imageLoader: loader,
        diagnosticContext: ImageDiagnosticContext(
            purpose: .readerVisible,
            url: url
        )
    )
    await diagnostics.flush()

    XCTAssertEqual(asset.displaySize, CGSize(width: 40, height: 80))
}

private final class RecordingImageDiagnostics: @unchecked Sendable, ImageDiagnosticsRecording {
    private let lock = NSLock()
    private var storage: [ImageDiagnosticEvent] = []

    var events: [ImageDiagnosticEvent] {
        lock.withLock { storage }
    }

    func record(_ event: ImageDiagnosticEvent) {
        lock.withLock { storage.append(event) }
    }
}
```

Add `GatedImageDataLoader` in the same test file. It implements both protocol methods, suspends `loadResult(from:diagnosticContext:)` on the injected `TestAsyncGate`, and returns the test bytes with one fixed non-nil `networkRequestID`. The test opens the gate only after the diagnostics recorder observes `.coalescing/.joined`, so it proves the decode-coalescing layer propagates the actual lower-layer ID to both callers without timing sleeps.

In the same red phase, make these diagnostics assertions concrete:

- Extend `testImageLoaderDiscardsUndecodableCachedResponseAndReloads` with an injected recorder/context and assert `.responseCache/.evicted`, `responseBytes` equal to the HTML byte count, and `metadata.contentType == "text/html"`.
- Extend `testImageCacheEvictsHeaderOnlyCachedImageAndReloadsDecodablePixels` and assert one `.decode/.failed`, then `.responseCache/.evicted`, then a final `.load/.succeeded` under the same caller ID.
- Add `testImageLoaderRecords429RetryBeforeSuccess`: return 429 once and valid JPEG once with zero retry delay; assert HTTP 429 response, `.retrying` attempt 1, and final success.
- Add `testImageLoaderRecordsTimeoutRetryExhaustion`: make `MockURLProtocol` throw `URLError(.timedOut)` for all three attempts; assert two `.retrying` events, one terminal `.network/.failed` with the timeout code, and no `.network/.succeeded`.
- Extend `testDecodedCacheTracksActualCostAndEviction` with an injected recorder; direct `setAsset` insertions use fresh `.unspecified` contexts. After the count-limit eviction, assert `.decodedCache/.evicted` names the first cache identity and contains no response data.
- Extend the existing last-waiter/data-clear cancellation tests with contexts and assert at least one `.cancelled` event and no `.failed` event for the cancelled caller IDs.

- [ ] **Step 2: Run the four new tests and verify missing overload/context failures**

Run:

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaTests/ImagePipelineTests/testCoalescingRegistryReportsSharedOperationIDToBothWaiters",
    "-only-testing:bikaTests/ImagePipelineTests/testImagePipelineRecordsCacheNetworkRetryDecodeAndSuccessTimeline",
    "-only-testing:bikaTests/ImagePipelineTests/testCoalescedImageCacheCallersReceiveSameActualNetworkRequestID",
    "-only-testing:bikaTests/ImagePipelineTests/testDiagnosticsPersistenceFailureDoesNotChangeImagePipelineResult"
  ],
  "progress": true
})
```

Expected: build failure for missing `CoalescingTaskRegistration`, `diagnostics`, or `diagnosticContext`.

- [ ] **Step 3: Add coalescing registration without changing existing cancellation semantics**

In `bika/Support/ImageDataLoader.swift`, add:

```swift
nonisolated struct CoalescingTaskRegistration: Equatable, Sendable {
    let operationID: UUID
    let joinedExistingOperation: Bool
}
```

Add a new overload whose operation receives the registry entry ID:

```swift
nonisolated func value(
    for key: Key,
    onRegistration: @escaping @Sendable (CoalescingTaskRegistration) -> Void,
    operation: @escaping @Sendable (UUID) async throws -> Value
) async throws -> Value
```

Keep the existing overload and implement it by forwarding:

```swift
nonisolated func value(
    for key: Key,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await value(
        for: key,
        onRegistration: { _ in },
        operation: { _ in try await operation() }
    )
}
```

Thread `onRegistration` and the UUID-taking operation through `registeredValue` and `register`. In `register`:

```swift
if var entry = entries[key], entry.generation == generation {
    entry.waiters[waiterID] = continuation
    entries[key] = entry
    onRegistration(.init(operationID: entry.id, joinedExistingOperation: true))
    return
}

let entryID = UUID()
onRegistration(.init(operationID: entryID, joinedExistingOperation: false))
let task = Task { try await operation(entryID) }
```

Do not alter epoch, waiter cancellation, last-waiter task cancellation, or stale-completion guards.

- [ ] **Step 4: Instrument `URLSessionImageDataLoader` and `ImageCache`**

Extend `ImageDataLoading` without breaking fixture/test conformers:

```swift
nonisolated struct ImageDataLoadResult: Sendable {
    let data: Data
    let networkRequestID: UUID?
}

func loadResult(
    from url: URL,
    diagnosticContext: ImageDiagnosticContext
) async throws -> ImageDataLoadResult

func invalidateCachedData(
    for url: URL,
    diagnosticContext: ImageDiagnosticContext
)

extension ImageDataLoading {
    func loadResult(
        from url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) async throws -> ImageDataLoadResult {
        ImageDataLoadResult(
            data: try await data(from: url),
            networkRequestID: nil
        )
    }

    func invalidateCachedData(
        for url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) {
        invalidateCachedData(for: url)
    }
}
```

Keep `URLSessionImageDataLoader.data(from:)` as a compatibility entry point that creates an `.unspecified` context, calls `loadResult`, and returns `.data`. Its live `loadResult` implementation uses `CoalescingTaskRegistration.operationID` as `networkRequestID` and returns it with the bytes.

Change `ImageCache`’s internal coalescing value from `DecodedImageAsset` to a private `(asset, networkRequestID)` result. The first decode operation receives the ID from `ImageDataLoadResult`; every caller waiting on the same decode task receives that same result and records its own `.load/.succeeded` event with the shared actual network ID. A decoded-memory-cache hit uses `networkRequestID: nil`.

Keep the existing `ImageCache.loadAsset(...)` signature as a compatibility overload that creates an `.unspecified` context and forwards to the contextual overload. The new contextual overload contains the real implementation. This guarantees old call sites still compile while live calls actually emit diagnostics.

On real decode failure, call the contextual invalidation overload so `.responseCache/.evicted` keeps the same caller `requestID`; retain the existing non-contextual invalidation requirement for fixture conformers and legacy calls.

Add `diagnostics: any ImageDiagnosticsRecording` to the cache initializer, defaulting to `ImageDiagnosticsService.shared`.

For `URLSessionImageDataLoader`, keep one shared stored recorder but provide platform-specific designated initializer declarations around the same assignments:

```swift
#if os(iOS)
init(
    session: URLSession,
    responseCache: URLCache,
    requestRegistry: CoalescingTaskRegistry<URL, Data> = .init(),
    diagnostics: any ImageDiagnosticsRecording = ImageDiagnosticsService.shared,
    retryDelays: [Duration] = [.milliseconds(200), .milliseconds(600)]
)
#else
init(
    session: URLSession,
    responseCache: URLCache,
    requestRegistry: CoalescingTaskRegistry<URL, Data> = .init(),
    retryDelays: [Duration] = [.milliseconds(200), .milliseconds(600)]
)
#endif
```

The macOS declaration assigns `ImageDiagnosticsNoopRecorder.shared`; the iOS declaration assigns its injected recorder. Keep the convenience initializers source-compatible on both platforms. This is the only platform conditional in the shared loader diagnostics wiring.

Create one internal event factory per file so all events use the supplied context and accept only an `Error?` for failure details; they must never accept raw error strings, headers, or bodies. Record:

- one `.load/.started` event at the contextual `ImageCache.loadAsset` entry point;
- response-cache hit/miss/eviction;
- coalescing registration with the shared operation ID;
- network start, HTTP response, retry, success, failure, and cancellation;
- decoded-cache hit/miss;
- decoded-cache replacement/automatic eviction;
- decode start/success/failure/cancellation;
- response-cache invalidation and the one bounded decode retry already present in the dirty worktree.

Populate `cacheIdentity` with `ImageCache.cacheIdentity(...)` and `decodeTarget` with `target.cacheKey`. For decode success, use `DecodedImageAsset.displaySize` as the orientation-corrected source size and the decoded image’s `cgImage` width/height (falling back to `image.size * image.scale`) as `decodedPixelSize`. Populate only the predefined event metadata fields: `pageStableID` from the context, HTTP MIME type as `contentType`, and whether the inspected response came from `URLCache`. Never add a generic metadata dictionary.

Extend `ImageCacheEntry` with its URL, cache identity, and insertion diagnostic context. Give `ImageCacheEvictionDelegate` the recorder and emit `.decodedCache/.evicted` from `willEvictObject`; also emit the same event when `storeAsset` explicitly replaces an existing entry. Do not enumerate or log image bytes during eviction.

Use `ContinuousClock` and convert duration to milliseconds:

```swift
let clock = ContinuousClock()
let startedAt = clock.now

private static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}

let durationMilliseconds = Self.milliseconds(startedAt.duration(to: clock.now))
```

Capture `durationMilliseconds` immediately before constructing each terminal event. Every `catch is CancellationError` and `URLError.cancelled` path records `.cancelled`, then rethrows the original cancellation. Never convert cancellation to `.failed`.

- [ ] **Step 5: Run image pipeline tests and commit exact files**

Run:

```text
test_sim({
  "extraArgs": ["-only-testing:bikaTests/ImagePipelineTests"],
  "progress": true
})
```

Expected: all image pipeline tests pass with zero warnings.

Before commit, stage only:

```bash
git add bika/Support/ImageDataLoader.swift \
        bika/Support/ImageCache.swift \
        bikaTests/ImagePipelineTests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "feat: trace image pipeline diagnostics"
```

Expected staged names: exactly the three paths above; Task 0 has already isolated the earlier image-recovery changes.

---

### Task 3: Propagate Cover, Visible Reader, Prefetch, and Display Contexts

**Files:**
- Modify: `bika/Views/Helpers/CachedAsyncImage.swift`
- Modify: `bika/Views/Helpers/MediaImageView.swift`
- Modify: `bika/Views/Helpers/ZoomableImageView.swift`
- Modify: `bika/Views/ComicReaderView.swift`
- Modify: `bikaTests/CachedAsyncImageTests.swift`
- Modify: `bikaTests/ImagePipelineTests.swift`

**Interfaces:**
- Consumes: `ImageDiagnosticContext`, `ImageDiagnosticPurpose`, `ImageDiagnosticsRecording`, and the instrumented cache/data loader.
- Produces:
  - `CachedAsyncImage.purpose`
  - `ZoomableImageView.diagnosticPurpose`
  - `ReaderImagePrefetchRequest.diagnosticContext`

- [ ] **Step 1: Write failing purpose and display-event tests**

In `bikaTests/CachedAsyncImageTests.swift`, add:

```swift
@MainActor
func testSuccessfulCoverLoadRecordsCoverDisplayEvent() async throws {
    let diagnostics = CachedImageDiagnosticsRecorder()
    let data = try makePNGData(size: CGSize(width: 40, height: 80))
    let state = CachedAsyncImageLoadingState()
    let url = URL(string: "https://images.bika.test/cover.jpg")!

    await state.load(
        url: url,
        targetSize: CGSize(width: 100, height: 150),
        contentMode: .fill,
        purpose: .cover,
        imageLoader: SizedImageLoader(dataByURL: [url: data]),
        imageCache: ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024),
        diagnostics: diagnostics,
        onImageSize: nil
    )

    XCTAssertTrue(diagnostics.events.contains {
        $0.purpose == .cover
            && $0.stage == .display
            && $0.action == .succeeded
    })
}

private final class CachedImageDiagnosticsRecorder:
    @unchecked Sendable,
    ImageDiagnosticsRecording
{
    private let lock = NSLock()
    private var storage: [ImageDiagnosticEvent] = []

    var events: [ImageDiagnosticEvent] {
        lock.withLock { storage }
    }

    func record(_ event: ImageDiagnosticEvent) {
        lock.withLock { storage.append(event) }
    }
}
```

In `bikaTests/ImagePipelineTests.swift`, extend the existing prefetch test:

```swift
XCTAssertEqual(
    requests.map(\.diagnosticContext.purpose),
    Array(repeating: .readerPrefetch, count: requests.count)
)
```

Add a coordinator assertion that a successful visible load records `.readerVisible/.display/.succeeded`.

- [ ] **Step 2: Run the selected tests and verify missing parameters**

Run:

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaTests/CachedAsyncImageTests/testSuccessfulCoverLoadRecordsCoverDisplayEvent",
    "-only-testing:bikaTests/ImagePipelineTests/testReaderImagePrefetcherReturnsRatiosByStablePageIdentity"
  ],
  "progress": true
})
```

Expected: compile failure for missing `purpose`, `diagnostics`, or `diagnosticContext`.

- [ ] **Step 3: Propagate purpose and context through cover loading**

In `CachedAsyncImageLoadingState.load`, add:

```swift
purpose: ImageDiagnosticPurpose,
diagnostics: any ImageDiagnosticsRecording,
```

Create one context before cache lookup:

```swift
let diagnosticContext = ImageDiagnosticContext(purpose: purpose, url: url)
```

Pass it to `imageCache.loadAsset`. On final success, record `.display/.succeeded`; on non-cancellation error, record `.display/.failed`; on cancellation, record `.display/.cancelled`.

Remove `CachedAsyncImageLoadingState`’s direct `imageCache.asset` fast path and always call the contextual `loadAsset`; `loadAsset` performs the same synchronous decoded-cache lookup and can therefore record both `.load/.started` and `.decodedCache/.hit`.

Add to `CachedAsyncImage`:

```swift
var purpose: ImageDiagnosticPurpose = .unspecified
var diagnostics: any ImageDiagnosticsRecording = ImageDiagnosticsService.shared
```

Pass both into state loading. In `MediaImageView`, set:

```swift
purpose: .cover
```

Set the direct `CachedAsyncImage` use in `ComicCardView.swift` to `purpose: .cover`; it does not go through `MediaImageView`.

- [ ] **Step 4: Propagate visible-reader and prefetch contexts**

Add to `ZoomableImageView`:

```swift
var diagnosticPurpose: ImageDiagnosticPurpose = .readerVisible
var diagnostics: any ImageDiagnosticsRecording = ImageDiagnosticsService.shared
```

When a coordinator begins an identity load, create one `ImageDiagnosticContext` and capture it in the task. Pass it to `ImageCache.loadAsset`, then record display success/failure/cancellation using the same request ID.

For the optional stable page field, derive only:

```swift
let pageStableID = parent.pageID.map {
    $0.backendPageID ?? $0.imageURL.absoluteString
}
```

Do not record `episodeID`, comic titles, account data, or any other reader state.

Extend `ReaderImagePrefetchRequest`:

```swift
let diagnosticContext: ImageDiagnosticContext
```

Construct requests with:

```swift
diagnosticContext: ImageDiagnosticContext(
    purpose: .readerPrefetch,
    url: url,
    pageStableID: pageID.backendPageID ?? pageID.imageURL.absoluteString
)
```

Pass the stored context into the prefetch cache load. Do not reuse a visible page request ID for prefetch.

Remove `ReaderImagePrefetcher`’s direct `imageCache.asset` fast path for the same reason; the contextual `loadAsset` preserves the cache hit while making it observable.

- [ ] **Step 5: Run focused regressions and commit**

Run:

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaTests/CachedAsyncImageTests",
    "-only-testing:bikaTests/ImagePipelineTests",
    "-only-testing:bikaTests/ReaderViewModelTests"
  ],
  "progress": true
})
```

Expected: all selected tests pass; no viewport, aspect-ratio, cancellation, or cache regressions.

Then:

```bash
git add bika/Views/Helpers/CachedAsyncImage.swift \
        bika/Views/Helpers/MediaImageView.swift \
        bika/Views/Helpers/ZoomableImageView.swift \
        bika/Views/ComicReaderView.swift \
        bika/Views/ComicCardView.swift \
        bikaTests/CachedAsyncImageTests.swift \
        bikaTests/ImagePipelineTests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "feat: correlate image diagnostics by purpose"
```

Do not stage `ReaderViewportUpdate.swift`, `ReaderViewModelTests.swift`, or `BikaSmokeUITests.swift`; Task 0 has already checkpointed their toolbar/viewport changes.

---

### Task 4: Add Settings Status, Clear, and JSON Export

**Files:**
- Modify: `bika/ViewModels/SettingsViewModel.swift`
- Modify: `bikaTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `ImageDiagnosticsManaging`, `ImageDiagnosticsMetadata`.
- Produces:
  - `imageDiagnosticsCountDescription`
  - `imageDiagnosticsLastErrorDescription`
  - `imageDiagnosticsMessage`
  - `isRefreshingImageDiagnostics`
  - `isClearingImageDiagnostics`
  - `isExportingImageDiagnostics`
  - `refreshImageDiagnostics()`
  - `clearImageDiagnostics()`
  - `exportImageDiagnostics() -> URL?`

- [ ] **Step 1: Write failing ViewModel tests**

Add to `bikaTests/SettingsViewModelTests.swift`:

```swift
@MainActor
func testRefreshAndClearImageDiagnosticsUpdatesDescriptions() async {
    let diagnostics = StubImageDiagnosticsManager(
        status: ImageDiagnosticsStatus(
            eventCount: 12,
            lastErrorAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    )
    let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

    await viewModel.refreshImageDiagnostics()
    XCTAssertEqual(viewModel.imageDiagnosticsCountDescription, "12 条")
    XCTAssertNotEqual(viewModel.imageDiagnosticsLastErrorDescription, "暂无错误")

    await viewModel.clearImageDiagnostics()
    XCTAssertEqual(viewModel.imageDiagnosticsCountDescription, "0 条")
    XCTAssertEqual(viewModel.imageDiagnosticsMessage, "图片诊断日志已清空")
}

@MainActor
func testExportImageDiagnosticsReturnsFileAndUsesAppMetadata() async throws {
    let diagnostics = StubImageDiagnosticsManager(
        status: ImageDiagnosticsStatus(eventCount: 1, lastErrorAt: nil)
    )
    let expectedURL = URL(fileURLWithPath: "/tmp/export.json")
    await diagnostics.setExportURL(expectedURL)
    let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

    let result = await viewModel.exportImageDiagnostics()

    XCTAssertEqual(result, expectedURL)
    let metadata = await diagnostics.lastMetadata
    XCTAssertEqual(metadata?.appVersion, "1.0")
    XCTAssertEqual(metadata?.imageQuality, ImageQuality.original.rawValue)
}

@MainActor
func testClearFailureKeepsCountAndShowsMessage() async {
    let diagnostics = StubImageDiagnosticsManager(
        status: ImageDiagnosticsStatus(eventCount: 7, lastErrorAt: nil),
        clearError: URLError(.cannotWriteToFile)
    )
    let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

    await viewModel.refreshImageDiagnostics()
    await viewModel.clearImageDiagnostics()

    XCTAssertEqual(viewModel.imageDiagnosticsCountDescription, "7 条")
    XCTAssertTrue(
        viewModel.imageDiagnosticsMessage?.hasPrefix("清空图片诊断日志失败：") == true
    )
}

@MainActor
func testExportFailureReturnsNilWithoutClearingLogs() async {
    let diagnostics = StubImageDiagnosticsManager(
        status: ImageDiagnosticsStatus(eventCount: 7, lastErrorAt: nil),
        exportError: URLError(.cannotCreateFile)
    )
    let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

    let result = await viewModel.exportImageDiagnostics()

    XCTAssertNil(result)
    let clearCallCount = await diagnostics.clearCallCount
    XCTAssertEqual(clearCallCount, 0)
    XCTAssertTrue(
        viewModel.imageDiagnosticsMessage?.hasPrefix("导出图片诊断日志失败：") == true
    )
}
```

Provide a private `StubImageDiagnosticsManager` actor implementing all protocol requirements, including a `nonisolated record(_:)` no-op, configurable `clearError`/`exportError`, `clearCallCount`, captured `lastMetadata`, and a `makeSettingsViewModel` helper that injects it.
The helper must inject build number `"42"` and:

```swift
ImageDiagnosticsDeviceInfo(
    model: "iPhone-Test",
    systemName: "iOS",
    systemVersion: "26.5"
)
```

- [ ] **Step 2: Run Settings tests and verify missing API failures**

Run:

```text
test_sim({
  "extraArgs": ["-only-testing:bikaTests/SettingsViewModelTests"],
  "progress": true
})
```

Expected: compile failure for missing initializer parameter or ViewModel properties.

- [ ] **Step 3: Implement injected diagnostics management**

Add these initializer dependencies to `SettingsViewModel`:

```swift
imageDiagnostics: any ImageDiagnosticsManaging = ImageDiagnosticsService.shared,
buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知",
deviceInfo: ImageDiagnosticsDeviceInfo = .current
```

Add `import Darwin` beside the existing SwiftUI import. Define `ImageDiagnosticsDeviceInfo` as an internal iOS-facing `Sendable` value in `SettingsViewModel.swift` so tests can inject deterministic metadata:

```swift
nonisolated struct ImageDiagnosticsDeviceInfo: Equatable, Sendable {
    let model: String
    let systemName: String
    let systemVersion: String

    static var current: ImageDiagnosticsDeviceInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { value, element in
            guard let byte = element.value as? Int8, byte != 0 else { return }
            value.append(Character(UnicodeScalar(UInt8(byte))))
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return ImageDiagnosticsDeviceInfo(
            model: identifier.isEmpty ? "unknown" : identifier,
            systemName: "iOS",
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }
}
```

Implement refresh, clear, and export with independent loading flags. On clear failure, keep the existing count and set `"清空图片诊断日志失败：\(error.localizedDescription)"`. `exportImageDiagnostics()` returns nil and sets `"导出图片诊断日志失败：\(error.localizedDescription)"` on failure; it never clears logs.

Use one date formatter for “最近错误” and expose `"暂无错误"` when nil.

- [ ] **Step 4: Run Settings tests and all diagnostics tests**

Run:

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaTests/SettingsViewModelTests",
    "-only-testing:bikaTests/ImageDiagnosticsTests"
  ],
  "progress": true
})
```

Expected: all selected tests pass with no Swift 6 isolation warnings.

- [ ] **Step 5: Commit exact files**

```bash
git add bika/Support/ImageDiagnostics.swift \
        bika/ViewModels/SettingsViewModel.swift \
        bikaTests/SettingsViewModelTests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "feat: expose image diagnostics in settings"
```

Expected staged names: exactly the three paths above.

---

### Task 5: Add Privacy Confirmation, Export Share Sheet, and Clear UI

**Files:**
- Create: `bika/Views/Helpers/ActivityShareSheet.swift`
- Modify: `bika/Views/SettingsView.swift`
- Modify: `bikaUITests/BikaSmokeUITests.swift`

**Interfaces:**
- Consumes: Task 4 ViewModel API.
- Produces:
  - `DiagnosticsExportItem`
  - `ActivityShareSheet`
  - accessibility IDs under `settings.imageDiagnostics.*`

- [ ] **Step 1: Write failing UI smoke assertions**

Add a UI test that launches the existing authenticated smoke fixture, opens Settings, and checks:

```swift
func testSettingsShowsImageDiagnosticsAndPrivacyWarningBeforeExport() {
    let app = launchApp(resetState: true)
    openSettings(in: app)

    let count = app.staticTexts["settings.imageDiagnostics.count"]
    for _ in 0..<6 where !count.exists {
        app.swipeUp()
    }
    XCTAssertTrue(
        count.waitForExistence(timeout: 5)
    )
    app.buttons["settings.imageDiagnostics.export"].tap()

    XCTAssertTrue(
        app.staticTexts["导出文件包含完整图片 URL，请只发送给可信对象。"]
            .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(app.buttons["继续导出"].exists)
    app.buttons["取消"].tap()
}
```

Reuse the existing `openSettings(in:)` helper, which opens “我的” and taps `profile.openSettings`; do not navigate by screen coordinates.

- [ ] **Step 2: Run the new UI test and verify diagnostics controls are absent**

Run:

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaUITests/BikaSmokeUITests/testSettingsShowsImageDiagnosticsAndPrivacyWarningBeforeExport"
  ],
  "progress": true
})
```

Expected: FAIL because `settings.imageDiagnostics.count` does not exist.

- [ ] **Step 3: Implement the narrow activity-controller bridge**

Create `bika/Views/Helpers/ActivityShareSheet.swift`:

```swift
import SwiftUI
import UIKit

nonisolated struct DiagnosticsExportItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
```

- [ ] **Step 4: Add the Settings diagnostics section and confirmation flows**

In `SettingsView`, add state:

```swift
@State private var showImageDiagnosticsExportConfirmation = false
@State private var showClearImageDiagnosticsConfirmation = false
@State private var diagnosticsExportItem: DiagnosticsExportItem?
```

Add a “图片诊断” section with:

- count text ID `settings.imageDiagnostics.count`;
- last error text ID `settings.imageDiagnostics.lastError`;
- export button ID `settings.imageDiagnostics.export`;
- clear button ID `settings.imageDiagnostics.clear`;
- status message ID `settings.imageDiagnostics.message`.

Export button sets `showImageDiagnosticsExportConfirmation = true`. Confirmation text is exactly:

`导出文件包含完整图片 URL，请只发送给可信对象。`

Present that privacy warning with `.alert("导出图片诊断日志？", ...)`, with “取消” and “继续导出” buttons. The “继续导出” action calls:

```swift
Task {
    if let url = await viewModel.exportImageDiagnostics() {
        diagnosticsExportItem = DiagnosticsExportItem(url: url)
    }
}
```

Present:

```swift
.sheet(item: $diagnosticsExportItem) { item in
    ActivityShareSheet(fileURL: item.url)
}
```

Use a separate destructive confirmation for clear. On `.task`, refresh image-cache usage and image-diagnostics status with `async let`, then await both.

- [ ] **Step 5: Run UI/unit tests and commit**

Run:

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaTests/SettingsViewModelTests",
    "-only-testing:bikaUITests/BikaSmokeUITests/testSettingsShowsImageDiagnosticsAndPrivacyWarningBeforeExport"
  ],
  "progress": true
})
```

Expected: unit and UI tests pass.

Then:

```bash
git add bika/Views/Helpers/ActivityShareSheet.swift \
        bika/Views/SettingsView.swift \
        bikaUITests/BikaSmokeUITests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "feat: export image diagnostics from settings"
```

Task 0 already committed the reader-toolbar test, so the cached `BikaSmokeUITests.swift` diff here must contain only the diagnostics UI test.

---

### Task 6: Verify End-to-End Behavior and Review the Branch

**Files:**
- Verify all modified files.
- No production change unless a verification failure identifies a concrete regression.

**Interfaces:**
- Consumes all prior tasks.
- Produces a review-ready branch with fresh build/test evidence.

- [ ] **Step 1: Run formatting and worktree checks**

Run:

```bash
git diff --check
git status --short --branch
git diff --stat
```

Expected: no whitespace errors; every untracked file is intentional.

- [ ] **Step 2: Build the iOS app**

With XcodeBuildMCP defaults confirmed:

```text
build_sim({})
```

Expected: `SUCCEEDED`, zero errors, zero warnings.

- [ ] **Step 3: Run all iOS unit tests**

```text
test_sim({
  "extraArgs": ["-only-testing:bikaTests"],
  "progress": true
})
```

Expected: all iOS unit tests pass with zero failures.

- [ ] **Step 4: Build the macOS target that shares `ImageDataLoader`**

```bash
xcodebuild -project bika.xcodeproj \
           -scheme BikaMacos \
           -configuration Debug \
           -sdk macosx \
           CODE_SIGNING_ALLOWED=NO \
           build
```

Expected: `** BUILD SUCCEEDED **`. This catches any missing shared diagnostics type or accidental UIKit/iOS-store dependency in the shared loader.

- [ ] **Step 5: Run focused UI smoke tests**

```text
test_sim({
  "extraArgs": [
    "-only-testing:bikaUITests/BikaSmokeUITests/testSettingsShowsImageDiagnosticsAndPrivacyWarningBeforeExport",
    "-only-testing:bikaUITests/BikaSmokeUITests/testReaderCenterTapHidesAndShowsToolbar"
  ],
  "progress": true
})
```

Expected: both pass. If the simulator automation service reports an accessibility process mismatch, stop the stale simulator app, relaunch the test once, and report the infrastructure failure separately if it repeats.

- [ ] **Step 6: Perform independent review and final diff audit**

Use `superpowers:requesting-code-review` with:

- requirement: `docs/superpowers/specs/2026-07-25-image-diagnostics-export-design.md`;
- base commit: `a69b996`;
- current branch HEAD and uncommitted diff, if any;
- explicit review focus: privacy, bounded storage, cancellation, coalescing correlation, persistence failure isolation, and preservation of real image height.

Fix every Critical or Important issue with a failing regression test first. Then rerun Steps 1–5.

Finally inspect:

```bash
git log --oneline --decorate -8
git status --short --branch
git diff HEAD --stat
```

Expected: no accidental file changes and no unresolved Critical/Important review findings.
