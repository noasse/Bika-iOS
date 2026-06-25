import UIKit
import XCTest
@testable import bika

@MainActor
final class CachedAsyncImageTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testReloadsImageWhenURLChangesAfterInitialLoad() async throws {
        let runID = UUID().uuidString
        let firstURL = try XCTUnwrap(URL(string: "https://images.bika.test/\(runID)/first.png"))
        let secondURL = try XCTUnwrap(URL(string: "https://images.bika.test/\(runID)/second.png"))
        let loader = SizedImageLoader(dataByURL: [
            firstURL: try makePNGData(size: CGSize(width: 12, height: 12)),
            secondURL: try makePNGData(size: CGSize(width: 24, height: 24)),
        ], delayByURL: [
            secondURL: 200_000_000,
        ])
        let observedWidths = LockedValue<[Int]>([])
        let loadingState = CachedAsyncImageLoadingState()

        await load(
            state: loadingState,
            url: firstURL,
            loader: loader,
            observedWidths: observedWidths
        )

        XCTAssertEqual(Int(try XCTUnwrap(loadingState.image).size.width), 12)
        XCTAssertEqual(observedWidths.value, [12])

        let reloadTask = Task {
            await load(
                state: loadingState,
                url: secondURL,
                loader: loader,
                observedWidths: observedWidths
            )
        }

        await waitUntil {
            loadingState.image == nil
        }
        await reloadTask.value

        XCTAssertEqual(Int(try XCTUnwrap(loadingState.image).size.width), 24)
        XCTAssertEqual(observedWidths.value, [12, 24])
    }

    private func load(
        state loadingState: CachedAsyncImageLoadingState,
        url: URL,
        loader: SizedImageLoader,
        observedWidths: LockedValue<[Int]>
    ) async {
        await loadingState.load(
            url: url,
            targetSize: nil,
            imageLoader: loader,
            imageCache: .shared,
            onImageSize: { size in
                observedWidths.value.append(Int(size.width))
            }
        )
    }

    private func makePNGData(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        return try XCTUnwrap(image.pngData())
    }
}

private final class SizedImageLoader: @unchecked Sendable, ImageDataLoading {
    private let dataByURL: [URL: Data]
    private let delayByURL: [URL: UInt64]

    init(dataByURL: [URL: Data], delayByURL: [URL: UInt64] = [:]) {
        self.dataByURL = dataByURL
        self.delayByURL = delayByURL
    }

    func data(from url: URL) async throws -> Data {
        if let delay = delayByURL[url], delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }

        guard let data = dataByURL[url] else {
            throw URLError(.fileDoesNotExist)
        }
        return data
    }
}
