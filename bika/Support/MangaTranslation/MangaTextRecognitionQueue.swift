import Foundation

/// Runs page text recognition one page at a time, newest request first.
///
/// Recognition is seconds of CPU and Vision work per page. Started freely — one per page the
/// reader shows — pages scrolled past kept running, filled the cooperative thread pool, and the
/// page actually on screen waited behind them indefinitely. Worse, the work ran in a detached
/// task, and detached tasks do not inherit cancellation, so cancelling a scrolled-away page did
/// not stop its work at all.
///
/// So: one job runs at a time; waiting jobs are served last-in-first-out, because the most
/// recent request is the page the reader is looking at; a cancelled waiting job leaves the
/// queue; and cancelling a running job is forwarded into its work, which checks it.
actor MangaTextRecognitionQueue {
    static let shared = MangaTextRecognitionQueue()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var isRunning = false
    private var waiting: [Waiter] = []

    /// Number of jobs waiting for their turn. For tests and diagnostics.
    var waitingCount: Int { waiting.count }

    /// Runs `work` when its turn comes. Throws `CancellationError` if the caller is cancelled
    /// while waiting, or if `work` observes cancellation while running.
    func run<Value: Sendable>(
        priority: TaskPriority = .utility,
        _ work: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()

        // Off the actor, so a long synchronous job never blocks the queue's bookkeeping.
        let worker = Task.detached(priority: priority) { try work() }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            // A detached task does not inherit cancellation; pass it on explicitly.
            worker.cancel()
        }
    }

    private func acquire() async throws {
        guard isRunning else {
            isRunning = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        // Hand the turn straight to the newest waiter; the queue stays busy.
        if let next = waiting.popLast() {
            next.continuation.resume()
        } else {
            isRunning = false
        }
    }
}
