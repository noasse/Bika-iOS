import Foundation
import Dispatch
import XCTest
@testable import bika

final class MockURLProtocolTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testStopLoadingCancelsHandlerWithoutCallingClient() async throws {
        let handlerStarted = expectation(description: "handler started")
        let handlerCancelled = expectation(description: "handler cancelled")
        let clientCalled = expectation(description: "URLProtocol client called")
        clientCalled.isInverted = true
        let handlerGate = ContinuationGate()
        let client = RecordingURLProtocolClient {
            clientCalled.fulfill()
        }

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            handlerStarted.fulfill()

            return try await withTaskCancellationHandler {
                await handlerGate.wait()
                try Task.checkCancellation()
                return MockHTTPResponse(statusCode: 200, headers: [:], data: Data())
            } onCancel: {
                handlerCancelled.fulfill()
                handlerGate.open()
            }
        }

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://mock.bika.test/cancel")))
        let urlProtocol = MockURLProtocol(request: request, cachedResponse: nil, client: client)

        urlProtocol.startLoading()
        await fulfillment(of: [handlerStarted], timeout: 1)

        urlProtocol.stopLoading()

        await fulfillment(of: [handlerCancelled], timeout: 1)
        handlerGate.open()
        await fulfillment(of: [clientCalled], timeout: 0.25)
    }

    func testStopLoadingWaitsForInFlightClientCallbackAndSuppressesRemainingCallbacks() async throws {
        let callbackStarted = expectation(description: "client callback started")
        let stopTaskReady = expectation(description: "stop task ready")
        let stopReturnedEarly = expectation(description: "stopLoading returned during callback")
        stopReturnedEarly.isInverted = true
        let stopFinished = expectation(description: "stopLoading finished")
        let callbackGate = DispatchSemaphore(value: 0)
        let stopGate = ContinuationGate()
        let isCheckingEarlyReturn = LockedValue(true)
        let callbackCount = LockedValue(0)
        let client = RecordingURLProtocolClient {
            callbackCount.value += 1
            if callbackCount.value == 1 {
                callbackStarted.fulfill()
                callbackGate.wait()
            }
        }

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { _ in
            MockHTTPResponse(statusCode: 200, headers: [:], data: Data())
        }

        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://mock.bika.test/callback-race")))
        let urlProtocol = MockURLProtocol(request: request, cachedResponse: nil, client: client)

        urlProtocol.startLoading()
        await fulfillment(of: [callbackStarted], timeout: 1)

        Task.detached {
            stopTaskReady.fulfill()
            await stopGate.wait()
            urlProtocol.stopLoading()
            if isCheckingEarlyReturn.value {
                stopReturnedEarly.fulfill()
            }
            stopFinished.fulfill()
        }

        await fulfillment(of: [stopTaskReady], timeout: 1)
        stopGate.open()
        await fulfillment(of: [stopReturnedEarly], timeout: 0.25)

        isCheckingEarlyReturn.value = false
        callbackGate.signal()
        await fulfillment(of: [stopFinished], timeout: 1)

        XCTAssertEqual(callbackCount.value, 1)
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if isOpen {
                    return true
                }

                waiters.append(continuation)
                return false
            }

            if shouldResume {
                continuation.resume()
            }
        }
    }

    func open() {
        let continuations = lock.withLock {
            guard !isOpen else { return [CheckedContinuation<Void, Never>]() }
            isOpen = true
            defer { waiters.removeAll() }
            return waiters
        }

        continuations.forEach { $0.resume() }
    }
}

private final class RecordingURLProtocolClient: NSObject, URLProtocolClient, @unchecked Sendable {
    private let onCallback: @Sendable () -> Void

    init(onCallback: @escaping @Sendable () -> Void) {
        self.onCallback = onCallback
    }

    func urlProtocol(
        _ protocol: URLProtocol,
        wasRedirectedTo request: URLRequest,
        redirectResponse: URLResponse
    ) {
        onCallback()
    }

    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {
        onCallback()
    }

    func urlProtocol(
        _ protocol: URLProtocol,
        didReceive response: URLResponse,
        cacheStoragePolicy policy: URLCache.StoragePolicy
    ) {
        onCallback()
    }

    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
        onCallback()
    }

    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
        onCallback()
    }

    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) {
        onCallback()
    }

    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) {
        onCallback()
    }

    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) {
        onCallback()
    }
}
