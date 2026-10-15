import Foundation

/// Work done once per key, however many callers ask for it while it runs.
///
/// A page was recognised twice whenever two parts of the reader wanted it at once — the page
/// on screen and the prefetcher a moment before, or the translation and the debug overlay —
/// and the second request queued behind the first only to repeat it. Callers now join the
/// work in progress. The work is cancelled only when every caller waiting on it has been.
actor SharedWork<Value: Sendable> {
    private struct Entry {
        let task: Task<Value, Error>
        var waiters: Int
    }

    private var running: [String: Entry] = [:]

    /// Number of keys with work in progress. For tests.
    var inProgressCount: Int { running.count }

    func value(for key: String, _ work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let task: Task<Value, Error>
        if let entry = running[key] {
            task = entry.task
            running[key]?.waiters += 1
        } else {
            // Detached: the work must not run on this actor, nor end with whichever caller
            // happened to start it.
            task = Task.detached { try await work() }
            running[key] = Entry(task: task, waiters: 1)
        }
        defer { finished(key, task) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(key, task) }
        }
    }

    private func leave(_ key: String, _ task: Task<Value, Error>) {
        guard var entry = running[key], entry.task == task else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            task.cancel()
            running[key] = nil
        } else {
            running[key] = entry
        }
    }

    private func finished(_ key: String, _ task: Task<Value, Error>) {
        if running[key]?.task == task { running[key] = nil }
    }
}
