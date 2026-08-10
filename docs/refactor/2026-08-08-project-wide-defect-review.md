# 全项目缺陷复审

- 日期：2026-08-08
- 分支：`refactor/shared-domain-core`（阅读器四阶段完成后）
- 基线：单元 180 / UI Smoke 9 / macOS 单元 47，全绿
- 范围：iOS + macOS 全量代码，重点找**缺陷**，不谈风格

> 说明：以下每条都标注了我的确信度。凡是从代码推导而非运行时实测的，都明确写出来了。

---

## 高

### H1. 云同步每次调用泄漏一个 URLSession（确信）

`CloudHistorySyncService.makeClient()`（`CloudHistorySync.swift:386`）**每次调用都新建** `CloudHistoryClient`，
而后者在 init 里新建 `URLSession`：

```swift
} else {
    let delegate = CloudHistoryPinnedCertificateDelegate(pins: config.certificateSHA256Pins)
    self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
}
```

全项目**没有任何一处** `invalidateAndCancel()` 或 `finishTasksAndInvalidate()`（已 grep 确认）。

Apple 的文档对此写得很直白：带 delegate 的 URLSession 会**强引用 delegate 直到被显式 invalidate**，
不 invalidate 就会一直泄漏到进程退出。

**触发频率**：`upload` 由 `ReadingHistoryManager.record()` 调用，而 `record()` 由 `ComicDetailView` 在
每次打开漫画详情时调用一次。再加上 `delete` / `clear` / `fetchHistory`。
一次浏览会话翻 100 本漫画 ≈ 泄漏 100 个 URLSession + 100 个 pin delegate。

> 修正一下我可能给人的印象：这**不是**每翻一页泄漏一次，是每开一次详情页。严重度仍然够高，但没到那个程度。

**附带的性能问题**：即使不配 pin（走 `URLSession(configuration: .ephemeral)` 那条分支），
每次请求新建 session 也意味着**连接无法复用**，每次同步都要重新做一次 TLS 握手。

**修法**：`CloudHistorySyncService` 持有一个长生命周期的 client/session，配置变化时才重建，
重建前对旧 session 调 `finishTasksAndInvalidate()`。

### H2. 云同步的 bearer token 存在 UserDefaults（确信）

```swift
nonisolated func setCloudHistoryConfig(_ config: CloudHistoryConfig) {
    ...
    set(config.bearerToken, forKey: CloudHistoryConfig.StorageKeys.bearerToken)
}
```

`keyValueStore` 就是 `UserDefaultsKeyValueStore`，落到 plist。

对比一下：本体的 PicACG token 有一整套 `SecureTokenStore` —— Keychain、
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`、防复活的 suppression 状态机、SHA256 摘要校验。
**同样是长期有效的持有者凭证，一个进 Keychain，一个进 plist。**

这不是"云同步不重要"——它带 `Bearer` 头访问用户自建的历史服务器，泄漏即可读写该用户全部阅读历史。

**修法**：让 `SecureTokenStore` 泛化成可存多个 account，云同步 token 走同一条路径。

### H3. UI 测试脚手架进了 Release 包（确信）

这三个文件都在 `bika/`（生产 target，文件系统同步组），**没有任何 `#if DEBUG`**（已 grep 确认为 0）：

| 文件 | 行数 | 内容 |
|---|---|---|
| `Support/MockURLProtocol.swift` | 178 | 可拦截全部网络流量的 URLProtocol |
| `Support/SmokeFixtureRouter.swift` | 406 | 全套假响应路由 |
| `Support/UITestLaunchConfig.swift` | 90 | 由启动参数/环境变量激活 |

激活方式（`UITestLaunchConfig.swift:54`）：

```swift
let arguments = Set(processInfo.arguments)
let isEnabled = arguments.contains("-ui-testing") || environment["UI_TESTING"] == "1"
let preloadAuthenticatedSession = arguments.contains("-ui-authenticated") || ...
```

打开后 `AppDependencies` 会把 `MockURLProtocol` 装进 URLSession，并且能**预置一个已登录会话**
（`AppDependencies.swift:55`）——绕过登录流程。

**实际风险评估要诚实**：App Store 分发的应用，普通攻击者无法设置启动参数（需要调试器或越狱设备），
所以这**不是一个可远程利用的漏洞**。真实代价是：约 670 行测试代码进入生产二进制，
以及一个"生产代码里存在流量拦截 + 登录绕过开关"的结构性隐患。

**修法**：把这三个文件移进一个仅 Debug 编译的 target/条件编译块，或抽到单独的 SPM 模块只在测试时链接。

---

## 中

### M1. iOS 点赞仍然没有防重入（确信，首份报告已提出，仍未修）

`CommentsViewModel.likeComment`（`:178`）与 `ChildCommentsViewModel` 同款，
macOS 的 `MacCommentsModel:135` 有 `inFlightLikeCommentIDs` 守卫，iOS 没有。
点赞是切换语义，连点两次净效果被翻转两次。

这条在我第一份报告里就写了，属于跨端逻辑重复导致的漂移；这次阅读器专项没有涉及，**依旧是活的**。

### M2. iOS 章节分页异常被静默吞掉（确信，首份报告已提出，仍未修）

`ComicDetailViewModel.loadAllEpisodes()` 遇到分页停滞/重复/数据不全一律 `break` 且不设 `episodesError`，
用户看到被截断的章节列表且零提示；macOS 同场景给三种明确错误。同样仍是活的。

### M3. `ComicDetailViewModel` 完全没有失效请求守卫（确信）

实测计数：

- `bika/ViewModels/ComicDetailViewModel.swift` 中 `requestID` 相关标识：**0 处**
- `BikaMacos/Stores/MacComicDetailStore.swift`：**25 处**（三个独立的 request id）

后果：详情页的"重试"按钮或快速的 `load()` / `reloadEpisodes()` 交叠时，
两个并发加载都会写 `episodes`，而 `isLoadingEpisodes` 被先完成的那个 `defer` 置为 false ——
转圈停了但另一个还在跑，最终显示的是后写入者，不一定是用户最后触发的那次。

### M4. 阅读进度键无上限增长（确信）

`ReadingProgressManager` 给**每本漫画写一个独立的 UserDefaults 键**，只有
`removeAllForCurrentAccount()` 会清，平时不清理。历史记录有 `maxItems = 200` 上限，进度没有。
长期使用后 UserDefaults plist 会累积成千上万个键，拖慢每次启动时的 plist 加载。

---

## 低 / 加固建议

### L1. 离线时的无谓重试

`shouldRetry` 把 `.notConnectedToInternet` 列为可重试。完全离线时每张图都会走满重试与退避，
纯属浪费电与时间。建议把"确定性无网"与"瞬时故障"分开。

### L2. 诊断文件的静态保护级别

`ImageDiagnosticsStore.persistThrowing` 用 `data.write(to:options: .atomic)`，
未指定 `.completeFileProtection`，落在 iOS 默认的"首次解锁后可读"。

该文件记录的是**用户看过的图片 URL**——对这个应用来说约等于浏览记录。
这不算 bug，但属于值得提升的一档。导出文件已有 `maximumExportCount = 5` 上限，这点是好的。

### L3. 两处 `request.url!` 强解包

`CloudHistoryClient.fetchHistory` 里的 `URLComponents(url: request.url!, ...)`。
实际不可能为 nil（上一行刚由 `endpoint()` 赋值），但它是全项目仅有的 2 处强解包之一。

---

## 复审中确认"没有问题"的部分

为免误导，这些我查过，是好的：

- **传输安全**：`CloudHistoryConfig.isUsable` 强制 `scheme == "https"`，不存在明文回落；全项目无 `http://` 硬编码。
- **空 pin 的处理**：`certificateSHA256Pins` 为空时走无 delegate 的分支，不会变成"全部拒绝"，也不会变成"伪装成已校验"。
- **图片重试策略**：`shouldRetry` 对 HTTP 状态码的划分（408/425/429/5xx 可重试，4xx 其余不重试）是正确的。
- **诊断事件与导出**：都有数量上限，持久化失败有退避重试，不会无限增长。
- **历史记录**：`maxItems = 200`，有上限。
- **Keychain 属性**：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 选得对（不随 iCloud 备份漂移）。
- **`@unchecked Sendable`**：24 处，抽查的几处都有 `NSLock` 或本身线程安全（UserDefaults / NSCache）支撑，不是随手糊上去的。

---

## 建议处理顺序

1. **H1**（会真实泄漏，改动小，收益确定）
2. **M1 + M2**（两个用户可见缺陷，且是同一个根因：跨端逻辑重复。适合并入最初评估里的"共享领域层"阶段 1）
3. **H2**（凭证一致性）
4. **H3**（发版前该做的卫生）
5. **M3 / M4**
6. L 系列按需

---

## 我没有验证的部分

- 安全区那条推导（第一份阅读器报告里的）**仍未真机实测**，需要真实账号与网络，我做不到。
- H1 的泄漏是从 Apple 对 URLSession delegate 生命周期的明确约定 + 代码里零 invalidate 推出的，
  **没有用 Instruments 实测过**。方向我有把握，具体泄漏量应以 Allocations/Leaks 实测为准。
