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
        return (nsError.domain, nsError.code, description)
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
