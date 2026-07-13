import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import bika

final class ImagePipelineTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testDecodeAssetUsesDisplayOrientationForReportedSize() throws {
        let data = try makeJPEGData(
            size: CGSize(width: 40, height: 20),
            orientation: .right
        )

        let asset = try XCTUnwrap(
            ImageDecoding.decodeAsset(
                from: data,
                target: .fitWidth(100),
                scale: 1,
                overscan: 1
            )
        )

        XCTAssertEqual(asset.displaySize.width, 20, accuracy: 0.01)
        XCTAssertEqual(asset.displaySize.height, 40, accuracy: 0.01)
        XCTAssertEqual(asset.image.size.height / asset.image.size.width, 2, accuracy: 0.01)
    }

    @MainActor
    func testZoomingScrollViewRelayoutsImageAfterItsBoundsChange() throws {
        let scrollView = ZoomingImageScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let image = makeImage(size: CGSize(width: 200, height: 100))

        scrollView.setImage(image)
        scrollView.layoutIfNeeded()

        let imageView = try XCTUnwrap(scrollView.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(imageView.frame.origin.y, 170, accuracy: 0.01)

        scrollView.frame.size.height = 160
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        XCTAssertEqual(imageView.frame, CGRect(x: 0, y: 0, width: 320, height: 160))
    }

    func testImageLoaderCoalescesConcurrentRequestsForTheSameURL() async throws {
        let requestCount = LockedValue(0)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/coalesced.jpg"))
        let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = responseCache
        MockURLProtocol.requestHandler = { _ in
            requestCount.value += 1
            try await Task.sleep(nanoseconds: 100_000_000)
            return MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "image/jpeg"],
                data: Data(repeating: 7, count: 128)
            )
        }
        let loader = URLSessionImageDataLoader(
            session: URLSession(configuration: configuration),
            responseCache: responseCache
        )

        async let first = loader.data(from: url)
        async let second = loader.data(from: url)
        let values = try await [first, second]

        XCTAssertEqual(values[0], values[1])
        XCTAssertEqual(requestCount.value, 1)
    }

    func testImageCacheCoalescesConcurrentDecodeRequestsForTheSameVariant() async throws {
        let data = try makeJPEGData(
            size: CGSize(width: 40, height: 80),
            orientation: .up
        )
        let loader = CountingImageDataLoader(data: data)
        let cache = ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/decode-coalesced.jpg"))

        async let first = cache.loadAsset(
            for: url,
            target: .fitWidth(100),
            overscan: 2,
            imageLoader: loader
        )
        async let second = cache.loadAsset(
            for: url,
            target: .fitWidth(100),
            overscan: 2,
            imageLoader: loader
        )
        let assets = try await [first, second]

        XCTAssertEqual(assets[0].displaySize, assets[1].displaySize)
        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 1)
    }

    func testImageCacheKeepsZoomableAndThumbnailVariantsSeparate() throws {
        let cache = ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/variants.jpg"))
        let target = ImageDecodeTarget.fitWidth(100)
        let thumbnail = DecodedImageAsset(
            image: makeImage(size: CGSize(width: 100, height: 200)),
            displaySize: CGSize(width: 100, height: 200)
        )

        cache.setAsset(thumbnail, for: url, target: target, overscan: 1)

        XCTAssertNotNil(cache.asset(for: url, target: target, overscan: 1))
        XCTAssertNil(cache.asset(for: url, target: target, overscan: 2))
    }

    func testCacheControllerReportsAndClearsResponseAndDecodedCaches() async throws {
        let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
        let decodedCache = ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024)
        let controller = ImageCacheController(
            responseCache: responseCache,
            decodedCache: decodedCache
        )
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/cached.jpg"))
        let request = URLRequest(url: url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        ))
        responseCache.storeCachedResponse(
            CachedURLResponse(response: response, data: Data(repeating: 1, count: 256)),
            for: request
        )
        decodedCache.setImage(makeImage(size: CGSize(width: 20, height: 20)), for: url)

        let populatedUsage = await controller.usage()

        XCTAssertGreaterThan(populatedUsage.totalBytes, 0)
        XCTAssertNotNil(decodedCache.image(for: url))

        await controller.clear()

        let clearedUsage = await controller.usage()
        XCTAssertEqual(clearedUsage.totalBytes, 0)
        XCTAssertNil(responseCache.cachedResponse(for: request))
        XCTAssertNil(decodedCache.image(for: url))
    }

    private func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeJPEGData(
        size: CGSize,
        orientation: CGImagePropertyOrientation
    ) throws -> Data {
        let image = makeImage(size: size)
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor CountingImageDataLoader: ImageDataLoading {
    private let data: Data
    private(set) var loadCount = 0

    init(data: Data) {
        self.data = data
    }

    func data(from url: URL) async throws -> Data {
        loadCount += 1
        try await Task.sleep(for: .milliseconds(100))
        return data
    }
}
