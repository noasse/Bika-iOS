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

    func testDecodedAssetLayoutAspectRatioUsesRenderedImageSize() {
        let asset = DecodedImageAsset(
            image: makeImage(size: CGSize(width: 200, height: 500)),
            displaySize: CGSize(width: 200, height: 600)
        )

        XCTAssertEqual(asset.layoutAspectRatio, 2.5, accuracy: 0.001)
    }

    func testFillDecodePreservesEnoughPixelsOnTheTargetShortSide() throws {
        let data = try makeJPEGData(
            size: CGSize(width: 400, height: 100),
            orientation: .up
        )
        let targetSize = CGSize(width: 50, height: 50)

        let fitAsset = try XCTUnwrap(
            ImageDecoding.decodeAsset(
                from: data,
                target: .fit(targetSize),
                scale: 1
            )
        )
        let fillAsset = try XCTUnwrap(
            ImageDecoding.decodeAsset(
                from: data,
                target: .fill(targetSize),
                scale: 1
            )
        )
        let fitImage = try XCTUnwrap(fitAsset.image.cgImage)
        let fillImage = try XCTUnwrap(fillAsset.image.cgImage)

        XCTAssertLessThan(min(fitImage.width, fitImage.height), 50)
        XCTAssertGreaterThanOrEqual(min(fillImage.width, fillImage.height), 50)
        XCTAssertGreaterThan(max(fillImage.width, fillImage.height), 150)
        XCTAssertNotEqual(
            ImageCache.cacheIdentity(
                for: try XCTUnwrap(URL(string: "https://images.bika.test/content-mode.jpg")),
                target: .fit(targetSize)
            ),
            ImageCache.cacheIdentity(
                for: try XCTUnwrap(URL(string: "https://images.bika.test/content-mode.jpg")),
                target: .fill(targetSize)
            )
        )
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

    @MainActor
    func testPageStaysVisibleWhileItsRowHeightIsStillAnEstimate() throws {
        // A row sized from the estimated aspect ratio does not yet match the image's real one.
        // The page must still be drawn: hiding it until the two agreed is what turned a height
        // that never converged into a permanently blank page.
        let scrollView = ZoomingImageScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 500)
        )
        let image = makeImage(size: CGSize(width: 200, height: 500))

        scrollView.setImage(image, layoutAspectRatio: 2.5)
        scrollView.layoutIfNeeded()

        let imageView = try XCTUnwrap(
            scrollView.subviews.compactMap { $0 as? UIImageView }.first
        )
        XCTAssertFalse(imageView.isHidden)
        XCTAssertEqual(imageView.frame.width, 320, accuracy: 0.01)

        // Once the real ratio lands the row settles on an exact fit, still visible.
        scrollView.frame.size.height = 800
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        XCTAssertFalse(imageView.isHidden)
        XCTAssertEqual(imageView.frame, CGRect(x: 0, y: 0, width: 320, height: 800))
    }

    @MainActor
    func testPageThatFitsItsRowLetsTheChapterScrollThrough() throws {
        // The vertical reader's normal state: the row is exactly as tall as the page. The page's
        // own scroll view must not take the drag, or the chapter cannot be scrolled.
        let scrollView = ZoomingImageScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 800)
        )
        scrollView.setImage(makeImage(size: CGSize(width: 200, height: 500)), layoutAspectRatio: 2.5)
        scrollView.layoutIfNeeded()

        XCTAssertEqual(scrollView.contentSize, CGSize(width: 320, height: 800))
        XCTAssertFalse(scrollView.panGestureRecognizer.isEnabled)
        // Zooming must still be reachable from rest — the capability is kept, not removed.
        XCTAssertEqual(scrollView.maximumZoomScale, 4)
        XCTAssertTrue(scrollView.pinchGestureRecognizer?.isEnabled ?? false)
    }

    @MainActor
    func testPanComesBackOnceThePageIsZoomed() throws {
        let scrollView = ZoomingImageScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 800)
        )
        // Zooming needs the coordinator's viewForZooming, so drive the real delegate.
        let coordinator = ZoomableImageView(
            url: nil,
            imageLoader: CountingImageDataLoader(data: Data()),
            imageCache: ImageCache(countLimit: 1, totalCostLimit: 1_024)
        ).makeCoordinator()
        scrollView.delegate = coordinator

        scrollView.setImage(makeImage(size: CGSize(width: 200, height: 500)), layoutAspectRatio: 2.5)
        scrollView.layoutIfNeeded()
        XCTAssertFalse(scrollView.panGestureRecognizer.isEnabled)

        scrollView.setZoomScale(2, animated: false)
        scrollView.layoutIfNeeded()

        XCTAssertGreaterThan(scrollView.zoomScale, scrollView.minimumZoomScale)
        XCTAssertTrue(
            scrollView.panGestureRecognizer.isEnabled,
            "a zoomed page must be pannable"
        )
    }

    @MainActor
    func testTallPageKeepsItsOwnScrollingInTheHorizontalReader() throws {
        // A page taller than the viewport has somewhere to scroll, so it keeps the drag.
        let scrollView = ZoomingImageScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 500)
        )
        scrollView.setImage(makeImage(size: CGSize(width: 200, height: 500)), layoutAspectRatio: 2.5)
        scrollView.layoutIfNeeded()

        XCTAssertEqual(scrollView.contentSize.height, 800, accuracy: 0.01)
        XCTAssertTrue(scrollView.panGestureRecognizer.isEnabled)
    }

    @MainActor
    func testShortPageIsCenteredAcrossTheFullWidth() throws {
        let scrollView = ZoomingImageScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 500)
        )
        let image = makeImage(size: CGSize(width: 200, height: 100))

        scrollView.setImage(image, layoutAspectRatio: 0.5)
        scrollView.layoutIfNeeded()

        let imageView = try XCTUnwrap(
            scrollView.subviews.compactMap { $0 as? UIImageView }.first
        )
        XCTAssertFalse(imageView.isHidden)
        XCTAssertEqual(imageView.frame, CGRect(x: 0, y: 170, width: 320, height: 160))
    }

    @MainActor
    func testZoomableCoordinatorRepublishesAspectRatioWhenPageIdentityChangesForSameURL() async throws {
        let diagnostics = RecordingImageDiagnostics()
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/reused.jpg"))
        let target = ImageDecodeTarget.fitWidth(320)
        let cache = ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024)
        cache.setAsset(
            DecodedImageAsset(
                image: makeImage(size: CGSize(width: 200, height: 500)),
                displaySize: CGSize(width: 200, height: 600)
            ),
            for: url,
            target: target,
            overscan: 2
        )
        let firstPageID = ReaderPageID(
            episodeID: "episode-1",
            backendPageID: "page",
            imageURL: url
        )
        let secondPageID = ReaderPageID(
            episodeID: "episode-2",
            backendPageID: "page",
            imageURL: url
        )
        var publishedRatios: [CGFloat] = []
        let scrollView = ZoomingImageScrollView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 800)
        )
        let coordinator = ZoomableImageView(
            url: url,
            imageLoader: CountingImageDataLoader(data: Data()),
            imageCache: cache,
            decodeTarget: .fitWidth(320),
            pageID: firstPageID,
            diagnostics: diagnostics,
            onImageAspectRatio: { publishedRatios.append($0) }
        ).makeCoordinator()

        coordinator.loadImageIfNeeded(in: scrollView)
        await waitUntilAsync { publishedRatios.count == 1 }

        coordinator.parent = ZoomableImageView(
            url: url,
            imageLoader: CountingImageDataLoader(data: Data()),
            imageCache: cache,
            decodeTarget: .fitWidth(320),
            pageID: secondPageID,
            diagnostics: diagnostics,
            onImageAspectRatio: { publishedRatios.append($0) }
        )
        coordinator.loadImageIfNeeded(in: scrollView)
        await waitUntilAsync { publishedRatios.count == 2 }

        XCTAssertEqual(publishedRatios, [2.5, 2.5])
        XCTAssertEqual(diagnostics.events.filter {
            $0.purpose == .readerVisible
                && $0.stage == .display
                && $0.action == .succeeded
        }.count, 2)
    }

    func testReaderImagePrefetcherReturnsRatiosByStablePageIdentity() async throws {
        let firstURL = try XCTUnwrap(URL(string: "https://images.bika.test/first.jpg"))
        let secondURL = try XCTUnwrap(URL(string: "https://images.bika.test/second.jpg"))
        let target = ImageDecodeTarget.fitWidth(320)
        let cache = ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024)
        let firstPageID = ReaderPageID(
            episodeID: "episode",
            backendPageID: "first",
            imageURL: firstURL
        )
        let secondPageID = ReaderPageID(
            episodeID: "episode",
            backendPageID: "second",
            imageURL: secondURL
        )
        cache.setAsset(
            DecodedImageAsset(
                image: makeImage(size: CGSize(width: 200, height: 400)),
                displaySize: CGSize(width: 200, height: 900)
            ),
            for: firstURL,
            target: target,
            overscan: 2
        )
        cache.setAsset(
            DecodedImageAsset(
                image: makeImage(size: CGSize(width: 200, height: 600)),
                displaySize: CGSize(width: 200, height: 300)
            ),
            for: secondURL,
            target: target,
            overscan: 2
        )

        let requests = [
            ReaderImagePrefetchRequest(
                pageID: firstPageID,
                url: firstURL,
                target: target,
                diagnosticContext: ImageDiagnosticContext(
                    purpose: .readerPrefetch,
                    url: firstURL,
                    pageStableID: firstPageID.backendPageID
                )
            ),
            ReaderImagePrefetchRequest(
                pageID: secondPageID,
                url: secondURL,
                target: target,
                diagnosticContext: ImageDiagnosticContext(
                    purpose: .readerPrefetch,
                    url: secondURL,
                    pageStableID: secondPageID.backendPageID
                )
            ),
        ]
        let ratios = await ReaderImagePrefetcher.prefetch(
            requests: requests,
            imageLoader: CountingImageDataLoader(data: Data()),
            imageCache: cache
        )

        XCTAssertEqual(try XCTUnwrap(ratios[firstPageID]), 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ratios[secondPageID]), 3, accuracy: 0.001)
        XCTAssertEqual(
            requests.map(\.diagnosticContext.purpose),
            Array(repeating: .readerPrefetch, count: requests.count)
        )
    }

    func testPrefetchRequestEqualityIgnoresDiagnosticRequestID() throws {
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/prefetch-key.jpg"))
        let pageID = ReaderPageID(
            episodeID: "episode",
            backendPageID: "page",
            imageURL: url
        )
        let first = ReaderImagePrefetchRequest(
            pageID: pageID,
            url: url,
            target: .fitWidth(320),
            diagnosticContext: ImageDiagnosticContext(
                purpose: .readerPrefetch,
                url: url,
                pageStableID: "page"
            )
        )
        let second = ReaderImagePrefetchRequest(
            pageID: pageID,
            url: url,
            target: .fitWidth(320),
            diagnosticContext: ImageDiagnosticContext(
                purpose: .readerPrefetch,
                url: url,
                pageStableID: "page"
            )
        )

        XCTAssertNotEqual(
            first.diagnosticContext.requestID,
            second.diagnosticContext.requestID
        )
        XCTAssertEqual(first, second)
    }

    // MARK: - Reader decode target agreement
    //
    // The reader prefetches pages and then displays them. Both paths must decode against the
    // same target, or they key different cache entries and every page is fetched and decoded
    // twice. That defect shipped once: the prefetcher measured the safe-area-inset container
    // while the visible page measured its own scroll view bounds, which ignore the safe area.
    // Nothing asserted the two agreed, so a full green suite missed it.

    @MainActor
    func testReaderPrefetchAndVisibleLoadShareASingleFetchForTheSamePage() async throws {
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/reader-agreement.jpg"))
        let data = try makeJPEGData(size: CGSize(width: 200, height: 500), orientation: .up)
        let loader = CountingImageDataLoader(data: data)
        let diagnostics = RecordingImageDiagnostics()
        let cache = ImageCache(
            countLimit: 10,
            totalCostLimit: 4 * 1_024 * 1_024,
            diagnostics: diagnostics
        )

        // One measured content box, exactly as the reader now supplies it to both consumers.
        let contentSize = CGSize(width: 402, height: 874)
        let target = try XCTUnwrap(
            ReaderDecodeTargetResolver.target(mode: .horizontal, contentSize: contentSize)
        )
        let pageID = ReaderPageID(
            episodeID: "episode-1",
            backendPageID: "page-1",
            imageURL: url
        )

        _ = await ReaderImagePrefetcher.prefetch(
            requests: [
                ReaderImagePrefetchRequest(
                    pageID: pageID,
                    url: url,
                    target: target,
                    diagnosticContext: ImageDiagnosticContext(
                        purpose: .readerPrefetch,
                        url: url,
                        pageStableID: "page-1"
                    )
                )
            ],
            imageLoader: loader,
            imageCache: cache
        )
        let fetchesAfterPrefetch = await loader.loadCount
        XCTAssertEqual(fetchesAfterPrefetch, 1)

        let scrollView = ZoomingImageScrollView(
            frame: CGRect(origin: .zero, size: contentSize)
        )
        let coordinator = ZoomableImageView(
            url: url,
            imageLoader: loader,
            imageCache: cache,
            decodeTarget: target,
            pageID: pageID,
            diagnostics: diagnostics
        ).makeCoordinator()
        coordinator.loadImageIfNeeded(in: scrollView)

        await waitUntilAsync {
            diagnostics.events.contains {
                $0.purpose == .readerVisible
                    && $0.stage == .display
                    && $0.action == .succeeded
            }
        }

        // The visible page must have been served by the prefetched entry.
        let fetchesAfterDisplay = await loader.loadCount
        XCTAssertEqual(fetchesAfterDisplay, 1)
        XCTAssertTrue(
            diagnostics.events.contains {
                $0.purpose == .readerVisible
                    && $0.stage == .decodedCache
                    && $0.action == .hit
            }
        )
    }

    func testReaderDecodeTargetIsStableAcrossSubPointViewportJitter() throws {
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/jitter.jpg"))

        // Layout passes report slightly different sizes for the same box.
        let firstTarget = try XCTUnwrap(
            ReaderDecodeTargetResolver.target(
                mode: .horizontal,
                contentSize: CGSize(width: 402, height: 874)
            )
        )
        let jitteredTarget = try XCTUnwrap(
            ReaderDecodeTargetResolver.target(
                mode: .horizontal,
                contentSize: CGSize(width: 402.4, height: 873.6)
            )
        )

        XCTAssertEqual(
            ImageCache.cacheIdentity(for: url, target: firstTarget, overscan: 2),
            ImageCache.cacheIdentity(for: url, target: jitteredTarget, overscan: 2)
        )
    }

    func testGenuinelyDifferentViewportsStillKeepSeparateCacheEntries() throws {
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/rotation.jpg"))
        let portrait = try XCTUnwrap(
            ReaderDecodeTargetResolver.target(
                mode: .horizontal,
                contentSize: CGSize(width: 402, height: 874)
            )
        )
        let landscape = try XCTUnwrap(
            ReaderDecodeTargetResolver.target(
                mode: .horizontal,
                contentSize: CGSize(width: 874, height: 402)
            )
        )

        XCTAssertNotEqual(
            ImageCache.cacheIdentity(for: url, target: portrait, overscan: 2),
            ImageCache.cacheIdentity(for: url, target: landscape, overscan: 2)
        )
    }

    func testReaderModesResolveDifferentDecodeTargets() {
        let contentSize = CGSize(width: 402, height: 874)

        XCTAssertEqual(
            ReaderDecodeTargetResolver.target(mode: .horizontal, contentSize: contentSize),
            .fit(contentSize)
        )
        XCTAssertEqual(
            ReaderDecodeTargetResolver.target(mode: .vertical, contentSize: contentSize),
            .fitWidth(contentSize.width)
        )
    }

    func testReaderDecodeTargetRefusesToGuessBeforeLayoutIsMeasured() {
        // Returning a fallback target here is what splits the cache; the caller must wait.
        XCTAssertNil(
            ReaderDecodeTargetResolver.target(mode: .horizontal, contentSize: .zero)
        )
        XCTAssertNil(
            ReaderDecodeTargetResolver.target(mode: .vertical, contentSize: .zero)
        )
        XCTAssertNil(
            ReaderDecodeTargetResolver.target(
                mode: .horizontal,
                contentSize: CGSize(width: 402, height: 0)
            )
        )
        // Width alone is enough for the vertical reader.
        XCTAssertEqual(
            ReaderDecodeTargetResolver.target(
                mode: .vertical,
                contentSize: CGSize(width: 402, height: 0)
            ),
            .fitWidth(402)
        )
    }

    func testImageLoaderCoalescesConcurrentRequestsForTheSameURL() async throws {
        let requestCount = LockedValue(0)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/coalesced.jpg"))
        let validImageData = try makeJPEGData(
            size: CGSize(width: 40, height: 80),
            orientation: .up
        )
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
                data: validImageData
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

    func testImageLoaderDiscardsUndecodableCachedResponseAndReloads() async throws {
        let requestCount = LockedValue(0)
        let diagnostics = RecordingImageDiagnostics()
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/poisoned-cache.jpg"))
        let context = ImageDiagnosticContext(purpose: .cover, url: url)
        let validImageData = try makeJPEGData(
            size: CGSize(width: 40, height: 80),
            orientation: .up
        )
        let poisonedData = Data("<html>temporary error</html>".utf8)
        let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
        let cachedResponse = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        ))
        responseCache.storeCachedResponse(
            CachedURLResponse(
                response: cachedResponse,
                data: poisonedData
            ),
            for: URLRequest(url: url)
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = responseCache
        MockURLProtocol.requestHandler = { _ in
            requestCount.value += 1
            return MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "image/jpeg"],
                data: validImageData
            )
        }
        let loader = URLSessionImageDataLoader(
            session: URLSession(configuration: configuration),
            responseCache: responseCache,
            diagnostics: diagnostics
        )

        let loaded = try await loader.loadResult(
            from: url,
            diagnosticContext: context
        )

        XCTAssertEqual(loaded.data, validImageData)
        XCTAssertEqual(requestCount.value, 1)
        let eviction = try XCTUnwrap(diagnostics.events.first {
            $0.requestID == context.requestID
                && $0.stage == .responseCache
                && $0.action == .evicted
        })
        XCTAssertEqual(eviction.responseBytes, poisonedData.count)
        XCTAssertEqual(eviction.metadata.contentType, "text/html")
    }

    func testImageLoaderRetriesTemporaryServerFailure() async throws {
        let requestCount = LockedValue(0)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/transient-failure.jpg"))
        let validImageData = try makeJPEGData(
            size: CGSize(width: 40, height: 80),
            orientation: .up
        )
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
                    data: Data("try again".utf8)
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
            responseCache: responseCache
        )

        let loadedData = try await loader.data(from: url)

        XCTAssertEqual(loadedData, validImageData)
        XCTAssertEqual(requestCount.value, 2)
    }

    func testImageLoaderRecords429RetryBeforeSuccess() async throws {
        let diagnostics = RecordingImageDiagnostics()
        let requestCount = LockedValue(0)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/rate-limited.jpg"))
        let context = ImageDiagnosticContext(purpose: .readerVisible, url: url)
        let validImageData = try makeJPEGData(
            size: CGSize(width: 40, height: 80),
            orientation: .up
        )
        let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = responseCache
        MockURLProtocol.requestHandler = { _ in
            requestCount.value += 1
            if requestCount.value == 1 {
                return MockHTTPResponse(
                    statusCode: 429,
                    headers: ["Content-Type": "text/plain"],
                    data: Data("slow down".utf8)
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

        _ = try await loader.loadResult(
            from: url,
            diagnosticContext: context
        )

        let events = diagnostics.events.filter { $0.requestID == context.requestID }
        XCTAssertTrue(events.contains {
            $0.stage == .network && $0.action == .response && $0.httpStatus == 429
        })
        XCTAssertTrue(events.contains {
            $0.stage == .network && $0.action == .retrying && $0.retryAttempt == 1
        })
        XCTAssertTrue(events.contains {
            $0.stage == .network && $0.action == .succeeded
        })
    }

    func testImageLoaderRecordsTimeoutRetryExhaustion() async throws {
        let diagnostics = RecordingImageDiagnostics()
        let requestCount = LockedValue(0)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/timeout.jpg"))
        let context = ImageDiagnosticContext(purpose: .readerVisible, url: url)
        let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = responseCache
        MockURLProtocol.requestHandler = { _ in
            requestCount.value += 1
            throw URLError(.timedOut)
        }
        let loader = URLSessionImageDataLoader(
            session: URLSession(configuration: configuration),
            responseCache: responseCache,
            diagnostics: diagnostics,
            retryDelays: [.zero, .zero]
        )

        do {
            _ = try await loader.loadResult(
                from: url,
                diagnosticContext: context
            )
            XCTFail("重试耗尽后不应成功")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        let events = diagnostics.events.filter { $0.requestID == context.requestID }
        XCTAssertEqual(requestCount.value, 3)
        XCTAssertEqual(events.filter {
            $0.stage == .network && $0.action == .retrying
        }.count, 2)
        XCTAssertTrue(events.contains {
            $0.stage == .network
                && $0.action == .failed
                && $0.errorCode == URLError.timedOut.rawValue
        })
        XCTAssertFalse(events.contains {
            $0.stage == .network && $0.action == .succeeded
        })
    }

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
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/timeline.jpg"))
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
        let url = try XCTUnwrap(
            URL(string: "https://images.bika.test/shared-network-id.jpg")
        )
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
        let url = try XCTUnwrap(
            URL(string: "https://images.bika.test/persistence-failure.jpg")
        )
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

    func testCoalescingRegistryCancellingOneWaiterKeepsSharedOperationAlive() async throws {
        let registry = CoalescingTaskRegistry<String, Int>()
        let probe = RegistryOperationProbe(delayNanoseconds: 250_000_000, value: 42)

        let first = Task {
            try await registry.value(for: "same-key") {
                try await probe.run()
            }
        }
        let second = Task {
            try await registry.value(for: "same-key") {
                try await probe.run()
            }
        }

        await waitUntilAsync { await probe.startCount == 1 }
        first.cancel()

        do {
            _ = try await first.value
            XCTFail("取消的 waiter 不应收到共享结果")
        } catch is CancellationError {
            // Expected.
        }

        let secondValue = try await second.value
        let startCount = await probe.startCount
        let cancellationCount = await probe.cancellationCount
        XCTAssertEqual(secondValue, 42)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(cancellationCount, 0)
    }

    func testCoalescingRegistryCancellingLastWaiterCancelsSharedOperation() async throws {
        let registry = CoalescingTaskRegistry<String, Int>()
        let probe = RegistryOperationProbe(delayNanoseconds: 30_000_000_000, value: 42)
        let waiter = Task {
            try await registry.value(for: "last-waiter") {
                try await probe.run()
            }
        }

        await waitUntilAsync { await probe.startCount == 1 }
        waiter.cancel()

        do {
            _ = try await waiter.value
            XCTFail("取消的 waiter 不应成功")
        } catch is CancellationError {
            // Expected.
        }

        await waitUntilAsync { await probe.cancellationCount == 1 }
        let cancellationCount = await probe.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
    }

    func testCoalescingRegistryImmediatelyCancelledWaiterNeverStartsOperation() async {
        let registry = CoalescingTaskRegistry<String, Int>()
        let operationCount = LockedValue(0)
        let waiter = Task.detached(priority: .background) {
            try await registry.value(for: "cancel-before-register") {
                operationCount.value += 1
                return 1
            }
        }

        waiter.cancel()

        do {
            _ = try await waiter.value
            XCTFail("立即取消的 waiter 不应成功")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("预期 CancellationError，实际为 \(error)")
        }
        XCTAssertEqual(operationCount.value, 0)
    }

    func testCoalescingRegistryOldCompletionDoesNotRemoveReplacementEntry() async throws {
        let registry = CoalescingTaskRegistry<String, Int>()
        let gate = ManualValueGate()

        let oldWaiter = Task {
            try await registry.value(for: "reused-key") {
                await gate.wait(id: 1)
            }
        }
        await waitUntilAsync { await gate.startedIDs.contains(1) }
        oldWaiter.cancel()
        do {
            _ = try await oldWaiter.value
            XCTFail("旧 waiter 应被取消")
        } catch is CancellationError {
            // Expected.
        }

        let replacement = Task {
            try await registry.value(for: "reused-key") {
                await gate.wait(id: 2)
            }
        }
        await waitUntilAsync { await gate.startedIDs.contains(2) }

        await gate.resume(id: 1, value: 1)
        try await Task.sleep(for: .milliseconds(50))

        let joinedReplacement = Task {
            try await registry.value(for: "reused-key") {
                await gate.immediate(id: 3, value: 3)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        await gate.resume(id: 2, value: 2)

        let replacementValue = try await replacement.value
        let joinedValue = try await joinedReplacement.value
        let startedIDs = await gate.startedIDs
        XCTAssertEqual(replacementValue, 2)
        XCTAssertEqual(joinedValue, 2)
        XCTAssertEqual(startedIDs, [1, 2])
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

    func testImageCacheEvictsHeaderOnlyCachedImageAndReloadsDecodablePixels() async throws {
        let diagnostics = RecordingImageDiagnostics()
        let requestCount = LockedValue(0)
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/truncated-cache.jpg"))
        let context = ImageDiagnosticContext(purpose: .readerVisible, url: url)
        let validImageData = try makeJPEGData(
            size: CGSize(width: 40, height: 80),
            orientation: .up
        )
        let headerOnlyData = try makeHeaderOnlyImageData(from: validImageData)
        let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
        let cachedResponse = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        ))
        responseCache.storeCachedResponse(
            CachedURLResponse(response: cachedResponse, data: headerOnlyData),
            for: URLRequest(url: url)
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = responseCache
        MockURLProtocol.requestHandler = { _ in
            requestCount.value += 1
            return MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "image/jpeg"],
                data: validImageData
            )
        }
        let loader = URLSessionImageDataLoader(
            session: URLSession(configuration: configuration),
            responseCache: responseCache,
            diagnostics: diagnostics
        )
        let cache = ImageCache(
            countLimit: 10,
            totalCostLimit: 1_024 * 1_024,
            diagnostics: diagnostics
        )

        let asset = try await cache.loadAsset(
            for: url,
            target: .fitWidth(100),
            imageLoader: loader,
            diagnosticContext: context
        )

        XCTAssertEqual(asset.displaySize, CGSize(width: 40, height: 80))
        XCTAssertEqual(requestCount.value, 1)
        let events = diagnostics.events.filter {
            $0.requestID == context.requestID
        }
        let decodeFailureIndex = try XCTUnwrap(events.firstIndex {
            $0.stage == .decode && $0.action == .failed
        })
        XCTAssertEqual(events.filter {
            $0.stage == .decode && $0.action == .failed
        }.count, 1)
        let responseEvictionIndex = try XCTUnwrap(events.firstIndex {
            $0.stage == .responseCache && $0.action == .evicted
        })
        let loadSuccessIndex = try XCTUnwrap(events.firstIndex {
            $0.stage == .load && $0.action == .succeeded
        })
        XCTAssertLessThan(decodeFailureIndex, responseEvictionIndex)
        XCTAssertLessThan(responseEvictionIndex, loadSuccessIndex)
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

    func testDecodedCacheTracksActualCostAndEviction() async throws {
        let diagnostics = RecordingImageDiagnostics()
        let cache = ImageCache(
            countLimit: 1,
            totalCostLimit: 1_024 * 1_024,
            diagnostics: diagnostics
        )
        let firstURL = try XCTUnwrap(URL(string: "https://images.bika.test/cost-1.jpg"))
        let secondURL = try XCTUnwrap(URL(string: "https://images.bika.test/cost-2.jpg"))
        let firstImage = makeImage(size: CGSize(width: 20, height: 30))
        let secondImage = makeImage(size: CGSize(width: 10, height: 15))

        cache.setImage(firstImage, for: firstURL)
        XCTAssertEqual(cache.currentMemoryUsage, ImageDecoding.cacheCost(for: firstImage))

        cache.setImage(secondImage, for: secondURL)
        let cachedFirst = cache.image(for: firstURL)
        let cachedSecond = cache.image(for: secondURL)
        XCTAssertEqual([cachedFirst, cachedSecond].compactMap { $0 }.count, 1)
        let retainedCost = try XCTUnwrap(
            cachedFirst.map(ImageDecoding.cacheCost(for:))
                ?? cachedSecond.map(ImageDecoding.cacheCost(for:))
        )
        XCTAssertEqual(cache.currentMemoryUsage, retainedCost)

        let firstIdentity = ImageCache.cacheIdentity(
            for: firstURL,
            target: .full
        )
        await waitUntilAsync {
            diagnostics.events.contains {
                $0.stage == .decodedCache
                    && $0.action == .evicted
                    && $0.cacheIdentity == firstIdentity
            }
        }
        let eviction = try XCTUnwrap(diagnostics.events.first {
            $0.stage == .decodedCache
                && $0.action == .evicted
                && $0.cacheIdentity == firstIdentity
        })
        XCTAssertEqual(eviction.url, firstURL)
        XCTAssertNil(eviction.responseBytes)
    }

    func testClearingDecodedCacheCancelsInflightLoadAndPreventsRefill() async throws {
        let diagnostics = RecordingImageDiagnostics()
        let data = try makeJPEGData(
            size: CGSize(width: 40, height: 80),
            orientation: .up
        )
        let loader = ControlledImageDataLoader()
        let cache = ImageCache(
            countLimit: 10,
            totalCostLimit: 1_024 * 1_024,
            diagnostics: diagnostics
        )
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/clear-inflight.jpg"))
        let context = ImageDiagnosticContext(purpose: .readerVisible, url: url)
        let load = Task {
            try await cache.loadAsset(
                for: url,
                target: .fitWidth(100),
                imageLoader: loader,
                diagnosticContext: context
            )
        }

        await waitUntilAsync { await loader.loadCount == 1 }
        await cache.removeAllImages()

        do {
            _ = try await load.value
            XCTFail("清缓存应取消在途解码 waiter")
        } catch is CancellationError {
            // Expected.
        }

        await loader.resume(with: data)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(cache.asset(for: url, target: .fitWidth(100)))
        XCTAssertEqual(cache.currentMemoryUsage, 0)
        let events = diagnostics.events.filter {
            $0.requestID == context.requestID
        }
        XCTAssertTrue(events.contains { $0.action == .cancelled })
        XCTAssertFalse(events.contains { $0.action == .failed })
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

    func testCacheControllerUsageIncludesDecodedMemory() async throws {
        let responseCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        let decodedCache = ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024)
        let controller = ImageCacheController(
            responseCache: responseCache,
            decodedCache: decodedCache
        )
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/decoded-usage.jpg"))
        let image = makeImage(size: CGSize(width: 20, height: 20))
        decodedCache.setImage(image, for: url)

        let usage = await controller.usage()

        XCTAssertEqual(usage.memoryBytes, ImageDecoding.cacheCost(for: image))
        XCTAssertEqual(usage.diskBytes, 0)
    }

    func testCacheControllerClearCancelsInflightDataAndPreventsResponseRefill() async throws {
        let diagnostics = RecordingImageDiagnostics()
        let responseCache = URLCache(memoryCapacity: 1_024 * 1_024, diskCapacity: 0)
        let controller = ImageCacheController(
            responseCache: responseCache,
            decodedCache: ImageCache(countLimit: 10, totalCostLimit: 1_024 * 1_024)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = responseCache
        let didStart = LockedValue(false)
        MockURLProtocol.requestHandler = { _ in
            didStart.value = true
            try await Task.sleep(for: .seconds(30))
            return MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "image/jpeg"],
                data: Data(repeating: 1, count: 128)
            )
        }
        let loader = URLSessionImageDataLoader(
            session: URLSession(configuration: configuration),
            responseCache: responseCache,
            requestRegistry: controller.dataRequestRegistry,
            diagnostics: diagnostics
        )
        let url = try XCTUnwrap(URL(string: "https://images.bika.test/clear-response.jpg"))
        let context = ImageDiagnosticContext(purpose: .readerPrefetch, url: url)
        let load = Task {
            try await loader.loadResult(
                from: url,
                diagnosticContext: context
            )
        }

        await waitUntilAsync { didStart.value }
        await controller.clear()

        do {
            _ = try await load.value
            XCTFail("清缓存应取消在途 data waiter")
        } catch is CancellationError {
            // Expected.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession may surface its cancellation as URLError.cancelled.
        }
        XCTAssertNil(responseCache.cachedResponse(for: URLRequest(url: url)))
        let events = diagnostics.events.filter {
            $0.requestID == context.requestID
        }
        XCTAssertTrue(events.contains { $0.action == .cancelled })
        XCTAssertFalse(events.contains { $0.action == .failed })
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

    private func makeHeaderOnlyImageData(from validImageData: Data) throws -> Data {
        for length in 1..<validImageData.count {
            let candidate = Data(validImageData.prefix(length))
            guard let source = CGImageSourceCreateWithData(candidate as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceGetType(source) != nil,
                  CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil else {
                continue
            }

            if ImageDecoding.decodeAsset(from: candidate, target: .fitWidth(100)) == nil {
                return candidate
            }
        }

        throw NSError(
            domain: "ImagePipelineTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "未能构造只含图片头、无法解码像素的测试数据"]
        )
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

private actor ControlledImageDataLoader: ImageDataLoading {
    private(set) var loadCount = 0
    private var continuation: CheckedContinuation<Data, Never>?

    func data(from url: URL) async throws -> Data {
        loadCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

private actor GatedImageDataLoader: ImageDataLoading {
    private let data: Data
    private let gate: TestAsyncGate
    private let networkRequestID = UUID()

    init(data: Data, gate: TestAsyncGate) {
        self.data = data
        self.gate = gate
    }

    func data(from url: URL) async throws -> Data {
        await gate.wait()
        return data
    }

    func loadResult(
        from url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) async throws -> ImageDataLoadResult {
        await gate.wait()
        return ImageDataLoadResult(
            data: data,
            networkRequestID: networkRequestID
        )
    }
}

private final class RecordingImageDiagnostics:
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

private actor RegistryOperationProbe {
    private let delayNanoseconds: UInt64
    private let value: Int
    private(set) var startCount = 0
    private(set) var cancellationCount = 0

    init(delayNanoseconds: UInt64, value: Int) {
        self.delayNanoseconds = delayNanoseconds
        self.value = value
    }

    func run() async throws -> Int {
        startCount += 1
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
            return value
        } catch {
            if error is CancellationError {
                cancellationCount += 1
            }
            throw error
        }
    }
}

private actor ManualValueGate {
    private(set) var startedIDs: [Int] = []
    private var continuations: [Int: CheckedContinuation<Int, Never>] = [:]

    func wait(id: Int) async -> Int {
        startedIDs.append(id)
        return await withCheckedContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func immediate(id: Int, value: Int) -> Int {
        startedIDs.append(id)
        return value
    }

    func resume(id: Int, value: Int) {
        continuations.removeValue(forKey: id)?.resume(returning: value)
    }
}

private func waitUntilAsync(
    timeout: TimeInterval = 2,
    condition: @escaping () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("等待异步条件超时")
}
