import Foundation
import XCTest
@testable import bika

final class MangaTextRecognitionQueueTests: XCTestCase {
    func testRunsOneJobAtATime() async throws {
        let queue = MangaTextRecognitionQueue()
        let tracker = ConcurrencyTracker()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await queue.run {
                        tracker.enter()
                        Thread.sleep(forTimeInterval: 0.02)
                        tracker.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        XCTAssertEqual(tracker.peak, 1)
    }

    func testWaitingJobsRunNewestFirst() async throws {
        let queue = MangaTextRecognitionQueue()
        let gate = DispatchSemaphore(value: 0)
        let order = OrderRecorder()

        let holding = OrderRecorder()
        let blocker = Task { try await queue.run { holding.append("holding"); gate.wait() } }
        try await waitUntil { !holding.values.isEmpty }

        var tasks: [Task<Void, Error>] = []
        for name in ["oldest", "middle", "newest"] {
            tasks.append(Task { try await queue.run { order.append(name) } })
            // Enqueue strictly one after another.
            let expected = tasks.count
            try await waitUntil { await queue.waitingCount == expected }
        }

        gate.signal()
        _ = try await blocker.value
        for task in tasks { try await task.value }

        // The newest request is the page on screen; it goes first.
        XCTAssertEqual(order.values, ["newest", "middle", "oldest"])
    }

    func testCancelledWaitingJobLeavesTheQueueWithoutRunning() async throws {
        let queue = MangaTextRecognitionQueue()
        let gate = DispatchSemaphore(value: 0)
        let ran = OrderRecorder()

        let holding = OrderRecorder()
        let blocker = Task { try await queue.run { holding.append("holding"); gate.wait() } }
        try await waitUntil { !holding.values.isEmpty }

        let waiter = Task { try await queue.run { ran.append("ran") } }
        try await waitUntil { await queue.waitingCount == 1 }

        waiter.cancel()
        do {
            try await waiter.value
            XCTFail("a cancelled waiting job must throw")
        } catch is CancellationError {}
        let remaining = await queue.waitingCount
        XCTAssertEqual(remaining, 0)

        gate.signal()
        _ = try await blocker.value
        XCTAssertTrue(ran.values.isEmpty, "the scrolled-away page's work must never run")
    }

    func testCancellingARunningJobReachesItsWork() async throws {
        let queue = MangaTextRecognitionQueue()
        let started = OrderRecorder()

        let job = Task {
            try await queue.run { () throws -> Void in
                started.append("started")
                // Stands in for the extractor, which checks between stages. Capped, so that if
                // cancellation does not arrive the job finishes and the test fails instead of
                // hanging the suite.
                let deadline = Date().addingTimeInterval(2)
                while Date() < deadline {
                    try Task.checkCancellation()
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
        try await waitUntil { !started.values.isEmpty }

        let clock = ContinuousClock()
        let cancelledAt = clock.now
        job.cancel()
        do {
            try await job.value
            XCTFail("a cancelled running job must throw")
        } catch is CancellationError {}

        // Before the fix, work in a detached task ignored cancellation and ran to completion.
        XCTAssertLessThan(cancelledAt.duration(to: clock.now), .seconds(1))

        // The queue is free again for the next page.
        let next = try await queue.run { 42 }
        XCTAssertEqual(next, 42)
    }

    // MARK: - Helpers

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                XCTFail("condition not met in time")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class ConcurrencyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var peak = 0

    func enter() {
        lock.withLock {
            current += 1
            peak = max(peak, current)
        }
    }

    func leave() {
        lock.withLock { current -= 1 }
    }
}

private final class OrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}
