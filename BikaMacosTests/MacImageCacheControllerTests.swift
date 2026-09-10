import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BikaMacos

final class MacImageCacheControllerTests: XCTestCase {
    func testUsageReportsTheResponseCacheFootprint() async throws {
        let responseCache = makeResponseCache()
        defer { responseCache.removeAllCachedResponses() }

        let controller = MacImageCacheController(
            responseCache: responseCache,
            decodedCache: { MacImageCache(imageLoader: MacEmptyImageLoader()) }
        )
        let emptyUsage = await controller.usage()
        XCTAssertEqual(emptyUsage.totalBytes, 0)

        let url = try XCTUnwrap(URL(string: "https://images.bika.test/usage.jpg"))
        store(byteCount: 64 * 1_024, for: url, in: responseCache)

        let usage = await controller.usage()
        XCTAssertGreaterThan(usage.totalBytes, 0)
        XCTAssertEqual(usage.totalBytes, usage.memoryBytes + usage.diskBytes)
    }

    func testClearEmptiesBothTheResponseCacheAndTheDecodedCache() async throws {
        let responseCache = makeResponseCache()
        defer { responseCache.removeAllCachedResponses() }

        let imageData = try makeJPEGData(size: CGSize(width: 60, height: 60))
        let decodedCache = MacImageCache(
            imageLoader: MacStaticImageLoader(data: imageData),
            countLimit: 10,
            totalCostLimit: 4 * 1_024 * 1_024
        )
        let controller = MacImageCacheController(
            responseCache: responseCache,
            decodedCache: { decodedCache }
        )

        let url = try XCTUnwrap(URL(string: "https://images.bika.test/clear.jpg"))
        let target = MacImageDecodeTarget.fit(CGSize(width: 30, height: 30))
        _ = try await decodedCache.asset(
            for: url,
            target: target,
            pixelScale: 2,
            maximumPixelSize: 512
        )
        store(byteCount: 32 * 1_024, for: url, in: responseCache)

        XCTAssertNotNil(
            decodedCache.cachedAsset(for: url, target: target, pixelScale: 2, maximumPixelSize: 512)
        )
        let populatedUsage = await controller.usage()
        XCTAssertGreaterThan(populatedUsage.totalBytes, 0)

        await controller.clear()

        XCTAssertNil(
            decodedCache.cachedAsset(for: url, target: target, pixelScale: 2, maximumPixelSize: 512)
        )
        let clearedUsage = await controller.usage()
        XCTAssertEqual(clearedUsage.totalBytes, 0)
    }

    // MARK: - Helpers

    private func makeResponseCache() -> URLCache {
        URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 0, directory: nil)
    }

    private func store(byteCount: Int, for url: URL, in cache: URLCache) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: Data(repeating: 0xAB, count: byteCount)),
            for: URLRequest(url: url)
        )
    }

    private func makeJPEGData(size: CGSize) throws -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private struct MacEmptyImageLoader: ImageDataLoading {
    func data(from url: URL) async throws -> Data {
        throw URLError(.cannotDecodeContentData)
    }
}

private struct MacStaticImageLoader: ImageDataLoading {
    let data: Data

    func data(from url: URL) async throws -> Data {
        data
    }
}
