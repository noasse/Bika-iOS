import Foundation
import UIKit

nonisolated protocol ImageDataLoading: Sendable {
    func data(from url: URL) async throws -> Data
}

final class URLSessionImageDataLoader: @unchecked Sendable, ImageDataLoading {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    convenience init() {
        self.init(session: .shared)
    }

    func data(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }
}

final class FixtureImageDataLoader: @unchecked Sendable, ImageDataLoading {
    private static let placeholderImageData: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))

            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 7, y: 7, width: 10, height: 10))
        }
        return image.pngData() ?? Data()
    }()

    func data(from url: URL) async throws -> Data {
        Self.placeholderImageData
    }
}
