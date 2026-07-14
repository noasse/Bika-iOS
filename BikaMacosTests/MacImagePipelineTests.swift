import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BikaMacos

final class MacImagePipelineTests: XCTestCase {
    func testDecodeAssetReportsEXIFCorrectedOriginalDisplaySize() throws {
        let data = try makeJPEGData(
            size: CGSize(width: 80, height: 40),
            orientation: .right
        )

        let asset = try XCTUnwrap(
            MacImageDecoding.decodeAsset(
                from: data,
                target: .fitWidth(120),
                pixelScale: 1,
                maximumPixelSize: 4_096
            )
        )

        XCTAssertEqual(asset.displaySize.width, 40, accuracy: 0.01)
        XCTAssertEqual(asset.displaySize.height, 80, accuracy: 0.01)
        XCTAssertEqual(asset.pixelSize.height / asset.pixelSize.width, 2, accuracy: 0.01)
    }

    func testDecodeAssetHonoursMaximumPixelSizeWithoutChangingDisplaySize() throws {
        let data = try makeJPEGData(
            size: CGSize(width: 400, height: 200),
            orientation: .up
        )

        let asset = try XCTUnwrap(
            MacImageDecoding.decodeAsset(
                from: data,
                target: .fitWidth(400),
                pixelScale: 8,
                maximumPixelSize: 128
            )
        )

        XCTAssertLessThanOrEqual(max(asset.pixelSize.width, asset.pixelSize.height), 128)
        XCTAssertEqual(asset.displaySize, CGSize(width: 400, height: 200))
    }

    func testFillTargetDecodesEnoughPixelsForTheShortEdge() throws {
        let data = try makeJPEGData(
            size: CGSize(width: 40, height: 200),
            orientation: .up
        )

        let asset = try XCTUnwrap(
            MacImageDecoding.decodeAsset(
                from: data,
                target: .fill(CGSize(width: 40, height: 40)),
                pixelScale: 1,
                maximumPixelSize: 1_024
            )
        )

        XCTAssertGreaterThanOrEqual(asset.pixelSize.width, 40)
    }

    func testMacImageCacheCoalescesConcurrentDecodeForSameVariant() async throws {
        let data = try makeJPEGData(
            size: CGSize(width: 60, height: 120),
            orientation: .up
        )
        let loader = MacCountingImageLoader(data: data)
        let cache = MacImageCache(imageLoader: loader, countLimit: 10, totalCostLimit: 1_024 * 1_024)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/mac-coalesced.jpg"))

        async let first = cache.asset(
            for: url,
            target: .fitWidth(120),
            pixelScale: 2,
            maximumPixelSize: 4_096
        )
        async let second = cache.asset(
            for: url,
            target: .fitWidth(120),
            pixelScale: 2,
            maximumPixelSize: 4_096
        )
        let assets = try await [first, second]

        XCTAssertEqual(assets[0].displaySize, assets[1].displaySize)
        let loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 1)
    }

    func testCacheIdentitySeparatesPixelScaleAndMaximumPixelSize() throws {
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/mac-variants.jpg"))

        let base = MacImageCache.cacheIdentity(
            for: url,
            target: .fitWidth(512),
            pixelScale: 2,
            maximumPixelSize: 8_192
        )
        let upgrade = MacImageCache.cacheIdentity(
            for: url,
            target: .fitWidth(512),
            pixelScale: 8,
            maximumPixelSize: 16_384
        )

        XCTAssertNotEqual(base, upgrade)
    }

    func testClearCancelsInFlightDecodeAndPreventsLateCacheRefill() async throws {
        let data = try makeJPEGData(
            size: CGSize(width: 80, height: 80),
            orientation: .up
        )
        let loader = MacGateImageLoader(data: data)
        let cache = MacImageCache(imageLoader: loader, countLimit: 10, totalCostLimit: 1_024 * 1_024)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/mac-clear.jpg"))

        let loadTask = Task {
            try await cache.asset(
                for: url,
                target: .fit(CGSize(width: 40, height: 40)),
                pixelScale: 2,
                maximumPixelSize: 512
            )
        }
        await loader.waitUntilRequested()

        await cache.removeAllImages()
        await loader.release()

        do {
            _ = try await loadTask.value
            XCTFail("被清理的旧任务不应成功回填缓存")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }

        XCTAssertNil(
            cache.cachedAsset(
                for: url,
                target: .fit(CGSize(width: 40, height: 40)),
                pixelScale: 2,
                maximumPixelSize: 512
            )
        )
    }

    func testReaderResolutionPlanBucketsViewportAndSeparatesBaseFromUpgrade() {
        XCTAssertEqual(MacReaderImageResolutionPlan.viewportBucket(for: 1_001), 1_024)
        XCTAssertEqual(MacReaderImageResolutionPlan.viewportBucket(for: 1_025), 1_152)

        let base = MacReaderImageResolutionPlan.variant(viewportWidth: 1_001, magnification: 1.24)
        XCTAssertEqual(base.viewportWidth, 1_024)
        XCTAssertEqual(base.pixelScale, 2)
        XCTAssertEqual(base.maximumPixelSize, 8_192)

        let upgrade = MacReaderImageResolutionPlan.variant(viewportWidth: 1_001, magnification: 1.25)
        XCTAssertEqual(upgrade.viewportWidth, 1_024)
        XCTAssertEqual(upgrade.pixelScale, 8)
        XCTAssertEqual(upgrade.maximumPixelSize, 16_384)
        XCTAssertNotEqual(base, upgrade)
    }

    private func makeJPEGData(
        size: CGSize,
        orientation: CGImagePropertyOrientation
    ) throws -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.5, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let cgImage = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private actor MacCountingImageLoader: ImageDataLoading {
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

private actor MacGateImageLoader: ImageDataLoading {
    private let data: Data
    private var requested = false
    private var released = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(data: Data) {
        self.data = data
    }

    func data(from url: URL) async throws -> Data {
        requested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        if !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return data
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
