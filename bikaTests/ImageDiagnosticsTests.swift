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
                    "Authorization: Bearer unit-test-token; Cookie=unit-test-cookie password=unit-test-password",
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
        ImageDiagnosticEvent(
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
