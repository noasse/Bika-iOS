import Foundation
import CryptoKit

nonisolated enum APISignature {
    /// Generate HMAC-SHA256 signature for PicACG API.
    /// - Parameters:
    ///   - path: API path (without leading slash), e.g. "auth/sign-in"
    ///   - method: HTTP method uppercase, e.g. "POST"
    ///   - timestamp: Unix timestamp string
    ///   - nonce: Nonce string
    /// - Returns: Hex-encoded HMAC-SHA256 signature (64 chars)
    static func sign(path: String, method: String, timestamp: String, nonce: String = APIConfig.nonce) -> String {
        // Raw = path + timestamp + nonce + method + apiKey, all lowercased
        let raw = (path + timestamp + nonce + method + APIConfig.apiKey).lowercased()

        let key = SymmetricKey(data: Data(APIConfig.secretKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(raw.utf8), using: key)

        return signature.map { String(format: "%02x", $0) }.joined()
    }
}
