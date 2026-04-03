import Foundation

extension NSLock {
    @discardableResult
    nonisolated func withLock<T>(_ action: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try action()
    }
}

nonisolated protocol KeyValueStore: AnyObject, Sendable {
    func string(forKey key: String) -> String?
    func integer(forKey key: String) -> Int
    func data(forKey key: String) -> Data?
    func stringArray(forKey key: String) -> [String]?

    func set(_ value: String?, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func set(_ value: Data?, forKey key: String)
    func set(_ value: [String]?, forKey key: String)
    func removeObject(forKey key: String)
    func resetPersistentState()
}

final nonisolated class UserDefaultsKeyValueStore: @unchecked Sendable, KeyValueStore {
    static let standard = UserDefaultsKeyValueStore(userDefaults: .standard)

    private let userDefaults: UserDefaults
    private let suiteName: String?

    init(userDefaults: UserDefaults, suiteName: String? = nil) {
        self.userDefaults = userDefaults
        self.suiteName = suiteName
    }

    convenience init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.init(userDefaults: defaults, suiteName: suiteName)
    }

    func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    func integer(forKey key: String) -> Int {
        userDefaults.integer(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }

    func stringArray(forKey key: String) -> [String]? {
        userDefaults.stringArray(forKey: key)
    }

    func set(_ value: String?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    func set(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    func set(_ value: Data?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    func set(_ value: [String]?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    func resetPersistentState() {
        if let suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
            userDefaults.synchronize()
            return
        }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleIdentifier)
            userDefaults.synchronize()
        }
    }
}

final nonisolated class InMemoryKeyValueStore: @unchecked Sendable, KeyValueStore {
    private let lock = NSLock()
    private var strings: [String: String] = [:]
    private var integers: [String: Int] = [:]
    private var dataValues: [String: Data] = [:]
    private var stringArrays: [String: [String]] = [:]

    func string(forKey key: String) -> String? {
        lock.withLock { strings[key] }
    }

    func integer(forKey key: String) -> Int {
        lock.withLock { integers[key] ?? 0 }
    }

    func data(forKey key: String) -> Data? {
        lock.withLock { dataValues[key] }
    }

    func stringArray(forKey key: String) -> [String]? {
        lock.withLock { stringArrays[key] }
    }

    func set(_ value: String?, forKey key: String) {
        lock.withLock {
            if let value {
                strings[key] = value
            } else {
                strings.removeValue(forKey: key)
            }
        }
    }

    func set(_ value: Int, forKey key: String) {
        lock.withLock {
            integers[key] = value
        }
    }

    func set(_ value: Data?, forKey key: String) {
        lock.withLock {
            if let value {
                dataValues[key] = value
            } else {
                dataValues.removeValue(forKey: key)
            }
        }
    }

    func set(_ value: [String]?, forKey key: String) {
        lock.withLock {
            if let value {
                stringArrays[key] = value
            } else {
                stringArrays.removeValue(forKey: key)
            }
        }
    }

    func removeObject(forKey key: String) {
        lock.withLock {
            strings.removeValue(forKey: key)
            integers.removeValue(forKey: key)
            dataValues.removeValue(forKey: key)
            stringArrays.removeValue(forKey: key)
        }
    }

    func resetPersistentState() {
        lock.withLock {
            strings.removeAll()
            integers.removeAll()
            dataValues.removeAll()
            stringArrays.removeAll()
        }
    }
}
