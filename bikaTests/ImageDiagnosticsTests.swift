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

    func testRepeatedAndOversizedCorruptStoresKeepOneBoundedBackup() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("image-diagnostics.json")

        for index in 0..<3 {
            try Data("not-json-\(index)".utf8).write(to: fileURL)
            _ = ImageDiagnosticsService(
                fileURL: fileURL,
                maximumEventCount: 2_000,
                exportDirectory: directory
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        }

        try Data(repeating: 0x58, count: 5 * 1_024 * 1_024 + 1).write(to: fileURL)
        _ = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )

        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertLessThanOrEqual(backups.count, 1)
        for backup in backups {
            let size = try backup.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertLessThanOrEqual(size, 5 * 1_024 * 1_024)
        }
    }

    func testExportIsStableJSONSnapshotWithoutCredentials() async throws {
        let directory = try makeTemporaryDirectory()
        let service = ImageDiagnosticsService(
            fileURL: directory.appendingPathComponent("events.json"),
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        let unsafeError = NSError(
            domain: "token=unit-test-domain-token",
            code: 401,
            userInfo: [
                NSLocalizedDescriptionKey:
                    """
                    Authorization: Bearer unit-test-token;
                    Authorization: Basic unit-test-basic-credential;
                    Cookie=unit-test-cookie password=unit-test-password
                    token=unit-test-raw-token access_token=unit-test-access-token
                    api-key=unit-test-api-key session_id=unit-test-session
                    https://images.bika.test/error.jpg?token=unit-test-url-token
                    """,
            ]
        )
        service.record(
            makeEvent(
                url: URL(
                    string:
                        "https://unit-test-user:unit-test-pass@images.bika.test/page.jpg?quality=original&token=unit-test-query-token&api-key=unit-test-query-key&auth_token=unit-test-auth-token&id_token=unit-test-id-token&credential=unit-test-credential&X-Amz-Credential=unit-test-amz-credential&X-Amz-Signature=unit-test-amz-signature"
                )!,
                cacheIdentity:
                    "https://images.bika.test/page.jpg?access_token=unit-test-cache-token&client_secret=unit-test-client-secret#original",
                pageStableID:
                    "https://images.bika.test/page.jpg?session_id=unit-test-page-session",
                error: unsafeError
            )
        )
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
        XCTAssertTrue(text.contains("redacted"))
        for secret in [
            "unit-test-user",
            "unit-test-pass",
            "unit-test-token",
            "unit-test-basic-credential",
            "unit-test-domain-token",
            "unit-test-cookie",
            "unit-test-password",
            "unit-test-raw-token",
            "unit-test-access-token",
            "unit-test-api-key",
            "unit-test-session",
            "unit-test-url-token",
            "unit-test-query-token",
            "unit-test-query-key",
            "unit-test-auth-token",
            "unit-test-id-token",
            "unit-test-credential",
            "unit-test-amz-credential",
            "unit-test-amz-signature",
            "unit-test-cache-token",
            "unit-test-client-secret",
            "unit-test-page-session",
        ] {
            XCTAssertFalse(text.contains(secret), "Export leaked \(secret)")
        }
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

    func testFlushRetriesAfterTransientPersistenceFailure() async throws {
        let directory = try makeTemporaryDirectory()
        let blockedDirectory = directory.appendingPathComponent("temporarily-blocked")
        try Data("file-blocks-directory".utf8).write(to: blockedDirectory)
        let fileURL = blockedDirectory.appendingPathComponent("events.json")
        let service = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )

        service.record(makeEvent(urlSuffix: "survives-transient-write-failure"))
        await service.flush()
        try FileManager.default.removeItem(at: blockedDirectory)
        try FileManager.default.createDirectory(
            at: blockedDirectory,
            withIntermediateDirectories: true
        )
        await service.flush()

        let recreated = ImageDiagnosticsService(
            fileURL: fileURL,
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        let snapshot = await recreated.snapshot()
        XCTAssertEqual(snapshot.map(\.url.lastPathComponent), [
            "survives-transient-write-failure.jpg",
        ])
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

    func testConcurrentExportsReturnDistinctExistingSnapshots() async throws {
        let directory = try makeTemporaryDirectory()
        let service = ImageDiagnosticsService(
            fileURL: directory.appendingPathComponent("events.json"),
            maximumEventCount: 2_000,
            exportDirectory: directory
        )
        service.record(makeEvent(urlSuffix: "concurrent"))

        async let first = service.export(metadata: .fixture)
        async let second = service.export(metadata: .fixture)
        let urls = try await [first, second]

        XCTAssertNotEqual(urls[0], urls[1])
        for url in urls {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertFalse(try Data(contentsOf: url).isEmpty)
        }
    }

    private func makeEvent(urlSuffix: String, error: Error? = nil) -> ImageDiagnosticEvent {
        makeEvent(
            url: URL(string: "https://images.bika.test/\(urlSuffix).jpg")!,
            cacheIdentity: nil,
            pageStableID: "page-\(urlSuffix)",
            error: error
        )
    }

    private func makeEvent(
        url: URL,
        cacheIdentity: String?,
        pageStableID: String?,
        error: Error? = nil
    ) -> ImageDiagnosticEvent {
        ImageDiagnosticEvent(
            sequence: 0,
            timestamp: Date(),
            requestID: UUID(),
            networkRequestID: nil,
            purpose: .readerVisible,
            stage: .load,
            action: .started,
            url: url,
            cacheIdentity: cacheIdentity,
            httpStatus: nil,
            responseBytes: nil,
            durationMilliseconds: nil,
            retryAttempt: 0,
            decodeTarget: nil,
            sourcePixelSize: nil,
            decodedPixelSize: nil,
            error: error,
            metadata: ImageDiagnosticEventMetadata(
                pageStableID: pageStableID,
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
