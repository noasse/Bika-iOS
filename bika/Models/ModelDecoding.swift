import Foundation

extension KeyedDecodingContainer {
    nonisolated func decodeLossyIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    nonisolated func decodeFlexibleInt(forKey key: Key) throws -> Int {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "No value associated with key \(key.stringValue)"
                )
            )
        }

        if try decodeNil(forKey: key) {
            throw DecodingError.valueNotFound(
                Int.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected Int or numeric String"
                )
            )
        }

        if let value = try? decode(Int.self, forKey: key) {
            return value
        }

        if
            let rawValue = try? decode(String.self, forKey: key),
            let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return value
        }

        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Int or numeric String"
            )
        )
    }

    nonisolated func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if
            let rawValue = try? decode(String.self, forKey: key),
            let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return value
        }

        return nil
    }
}
