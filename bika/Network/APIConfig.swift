import Foundation

nonisolated enum APIConfig {
    static let baseURL = "https://picaapi.picacomic.com/"

    // HMAC signing keys
    static let apiKey = "C69BAF41DA5ABD1FFEDC6D2FEA56B"
    static let secretKey = "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"
    static let nonce = "b1ab87b4800d4d4590a11701b8551afa"

    // Static header values
    static let channel: String = "1"
    static let version: String = "2.2.1.2.3.3"
    static let buildVersion: String = "44"
    static let platform: String = "android"
    static let userAgent: String = "okhttp/3.8.1"
    static let accept: String = "application/vnd.picacomic.com.v1+json"
    static let appUUID: String = "defaultUuid"
    static let imageQualityDefault: String = "original"
}

nonisolated enum ImageQuality: String, Sendable, CaseIterable {
    case original = "original"
    case low = "low"
    case medium = "medium"
    case high = "high"
}

nonisolated enum SortMode: String, Sendable, CaseIterable {
    case defaultSort = "ua"   // 默认
    case newest = "dd"        // 新到旧
    case oldest = "da"        // 旧到新
    case liked = "ld"         // 最多爱心
    case views = "vd"         // 最多观看
}

nonisolated enum LeaderboardType: String, Sendable {
    case hour24 = "H24"
    case day7 = "D7"
    case day30 = "D30"
}
