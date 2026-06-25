import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))

            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 7, y: 7, width: 10, height: 10))
        }
        return image.pngData() ?? Data()
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 24).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 10, height: 10)).fill()
        image.unlockFocus()

        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return Data()
        }
        return pngData
        #else
        return Data()
        #endif
    }()

    func data(from url: URL) async throws -> Data {
        Self.placeholderImageData
    }
}
