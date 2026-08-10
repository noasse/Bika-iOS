# Bika-iOS 架构评估报告

- 日期：2026-08-07
- 分支：`refactor/shared-domain-core`
- 基线提交：`f7fea74`（= `origin/main` 最新）
- 单元测试基线：**166 个用例，0 失败**（`./scripts/test.sh unit`）

---

## 一、结论先行

**这个项目不是屎山。**

按常见的代码腐化指标实测，结果和"屎山"的印象相反：

| 指标 | 实测值 | 评价 |
|---|---|---|
| 生产代码 `try!` / `as!` / 强解包 | **2 处** | 极低 |
| `TODO` / `FIXME` / `HACK` | **0** | 无欠账标记 |
| 依赖注入 | 全面协议化（`APIClientProtocol`、`TokenPersisting`、`KeychainAccessing`） | 良好 |
| 单元测试 | 166 用例全绿，另有 UI Smoke + macOS 单测 | 强 |
| 测试代码量 | 8,889 行 / 生产 19,501 行（**0.46 比值**） | 健康 |
| 分层 | Models / Network / ViewModels / Views / Support 清晰 | 良好 |
| 跨端复用 | macOS 已复用 iOS 的 `APIClient`、`APIEndpoint`、全部 Models | 良好 |

代码规模：117 个 Swift 文件，28,390 行（iOS 生产 12,686 / macOS 生产 6,815 / 测试 8,889）。

**真正的问题只有一个，但它很贵**：iOS 的 `ViewModels/` 和 macOS 的 `Stores/` 各自重写了同一套业务逻辑，
且两边已经**实际漂移出行为差异和 bug**。这不是"看着乱"，是正在产生用户可见的缺陷。

---

## 二、P0：跨端业务逻辑重复 + 已确认的行为漂移

### 2.1 重复面积

同一份领域逻辑写了两遍：

| 领域 | iOS | macOS | 说明 |
|---|---|---|---|
| 评论 | `ViewModels/CommentsViewModel.swift` (343) | `Stores/MacCommentsModel.swift` (315) | 状态字段几乎逐个对应 |
| 阅读器 | `ViewModels/ReaderViewModel.swift` (256) | `Stores/MacReaderViewModel.swift` (303) | 同款"翻完所有页"循环 |
| 详情 | `ViewModels/ComicDetailViewModel.swift` (199) | `Stores/MacComicDetailStore.swift` (375) | 同款"翻完所有章节"循环 |
| 列表 | `ViewModels/ComicResultsViewModel.swift` (362) | `Stores/MacLibraryListStore.swift` (473) | 同款分页 |
| 图片缓存 | `Support/ImageCache.swift` (551) | `Support/MacImageCache.swift` (444) | 键/淘汰/身份逻辑同构 |

`CommentsViewModel` 和 `MacCommentsModel` 的状态字段对照，几乎是一份复制：

```
comments / topComments / currentPage / totalPages / totalVisibleComments
isLoading / commentText / isSending / errorMessage / actionErrorMessage
comicId / client / activeRequestID / lastPaginationTriggerCommentID
```

方法名同样成对：`loadFirstPage` / `loadMoreIfNeeded` / `loadMore` / `postComment` / `likeComment` / `uniqueComments`。

### 2.2 漂移已经变成 bug（两个实例）

#### Bug A — iOS 点赞缺少重入保护

`BikaMacos/Stores/MacCommentsModel.swift:135`

```swift
func likeComment(id: String) async {
    guard inFlightLikeCommentIDs.insert(id).inserted else { return }   // ← 有防重入
    defer { inFlightLikeCommentIDs.remove(id) }
    ...
}
```

`bika/ViewModels/CommentsViewModel.swift:178`

```swift
func likeComment(id: String) async {
    // ← 没有任何防重入
    let response: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
    ...
}
```

`likeComment` 是**切换**语义。iOS 上快速连点两次会发出两个请求，净效果在服务端被翻转两次（赞→取消赞），
本地状态也被 apply 两次。macOS 已经修了，iOS 没有。

#### Bug B — iOS 章节分页异常时静默吞掉，用户看不到任何错误

`bika/ViewModels/ComicDetailViewModel.swift:63` `loadAllEpisodes()`：分页出现异常时一律 `break`，
**不设置 `episodesError`**——只有抛错才会设置。于是后端分页停滞/重复/数据不全时，
iOS 展示一个被截断（甚至空）的章节列表，界面上没有任何异常提示。

`BikaMacos/Stores/MacComicDetailStore.swift:283` `fetchAllEpisodes()` 对同样的情况给出明确错误：

```swift
guard page.page >= requestedPage else { return (result, "章节分页未继续前进") }
...
return (result, "章节页面数据不完整")
...
guard !newEpisodes.isEmpty else { return (result, "章节分页数据重复") }
```

另外 macOS 全程检查 `Task.isCancelled`，iOS 的 `loadAllEpisodes` 完全没有取消检查。

> 这两个 bug 不是本次重构"顺手发现的小问题"，而是**重复代码必然产生的后果**：
> 一边修了，另一边没人知道要同步。不消除重复，这类缺陷会持续产生。

---

## 三、P1：`activeRequestID` 竞态守卫被手写了 6 遍

"后发请求作废先发请求"这个模式，在 6 个类型里各写了一份裸的 `Int` 自增 + 比对：

```
bika/ViewModels/ComicResultsViewModel.swift
bika/ViewModels/ComicListViewModel.swift
bika/ViewModels/LeaderboardViewModel.swift
bika/ViewModels/CommentsViewModel.swift
bika/ViewModels/SearchViewModel.swift
BikaMacos/Stores/MacCommentsModel.swift
```

`MacComicDetailStore` 甚至同时维护三个（`activeDetailRequestID` / `activeEpisodeRequestID` /
`activeRecommendationRequestID`）。每一处都是"忘了比对就出竞态"的雷点，且无法被集中测试。

---

## 四、P2：视图文件过大

| 文件 | 行数 |
|---|---|
| `BikaMacos/Views/MacReaderWindowView.swift` | 1,237 |
| `bika/Views/ComicReaderView.swift` | 674 |
| `BikaMacos/Views/MacListPaneView.swift` | 568 |
| `BikaMacos/Views/MacComicDetailPane.swift` | 543 |

注意 `ComicReaderView.swift` 里混进了非视图逻辑：`ReaderVerticalImageLayout`（:528）、
`ReaderImagePrefetchRequest`、预取调度。这些是纯逻辑，应该移出视图文件——而且它们**已经是**
`nonisolated enum` 纯函数，移动成本极低、风险极低。

---

## 五、P3：单例 13 个

```
ImageCache.shared            ImageDiagnosticsService.shared    ImageCacheController.shared
CloudHistorySyncService.shared   ImageDiagnosticsNoopRecorder.shared   AccountSessionStore.shared
NavigationStateStore.shared  AppDependencies.shared            ReadingProgressManager.shared
ThemeManager.shared          BlockedCategoriesManager.shared   ReadingHistoryManager.shared
MacImageCache.shared
```

已经有 `AppDependencies` 这个聚合点，但没有贯彻——多数调用方仍直接摸 `.shared`。
这是**中等优先级**：它降低可测性，但当前测试套件靠协议注入已经绕开了大部分痛点，所以不紧急。

---

## 六、建议方案：沿用项目已有的提取模式

**关键点：不需要发明新架构。项目里已经有正确答案。**

`bika/Models/CommentModels.swift:52` 的 `CommentLikeReducer`：

```swift
nonisolated enum CommentLikeReducer {
    static func apply(action: ..., commentID: String, to comments: inout [Comment]) { ... }
}
```

一个 `nonisolated enum` + 纯静态函数 + 值类型 `inout`，**iOS 和 macOS 同时在用**。
`ReaderVerticalImageLayout` 是第二个例子。这个模式已经验证可行，只是没有推广。

### 分阶段计划（每阶段独立可验证、可回滚）

**阶段 0 — 固化安全网**
- 现状已绿（166 用例）。补充针对漂移点的**双端对拍测试**：同一输入喂给 iOS 和 macOS 两条路径，断言行为一致。
- 这一步先于任何改动，用来证明后续重构确实"功能不变"。

**阶段 1 — 抽取分页内核（收益最大）**
- 新增 `EpisodePaginator` / `PagePaginator` / `CommentPaginator`，纯函数式，输入"当前累积状态 + 一页响应"，
  输出"下一步动作（继续/停止/报错）"。
- 两端的 `loadAllEpisodes` / `fetchAllEpisodes` / `loadPages` 全部改为驱动同一个内核。
- **顺带修掉 Bug B**：统一采用 macOS 那套显式报错语义（更正确的一方）。

**阶段 2 — 抽取请求代次守卫**
- 一个小值类型替换 6 处手写 `activeRequestID`，集中测试竞态。

**阶段 3 — 抽取动作重入守卫**
- 把 macOS 的 `inFlightLikeCommentIDs` 提成共享的 in-flight 去重器，两端共用。**修掉 Bug A**。

**阶段 4 — 视图瘦身**
- 把 `ComicReaderView` 里的布局/预取逻辑移到 `Support/`，拆分 `MacReaderWindowView`。
- 纯移动，不改行为。

**阶段 5（可选）— 图片缓存泛型化**
- `ImageCache` / `MacImageCache` 的键、淘汰、`cacheIdentity` 逻辑对图片类型泛型化，
  `UIImage` / `NSImage` 差异留在薄适配层。
- 收益中等、改动面大，**建议放最后或先不做**。

### 明确不建议做的事

- **不要推倒重写架构。** 现有分层是合理的，重写会让 166 个单测 + UI Smoke + macOS 单测大面积失效，
  丢掉唯一能证明"功能不变"的凭据，回归风险极高而收益不明确。
- **不要为了消除单例而大改依赖注入。** 当前协议注入已经让核心逻辑可测，收益不抵风险。
- **不要合并 iOS 与 macOS 的 View 层。** 两端交互模型本就不同，UI 分开是正确的，重复的是**逻辑**不是**界面**。

---

## 七、验证方式

每个阶段结束后跑：

```bash
./scripts/test.sh all
```

覆盖 iOS 单元 + UI Smoke + macOS 单元。任一阶段不绿即回滚该阶段。

---

## 八、给决策者的一句话总结

代码质量本身没问题，别重写；把 iOS 和 macOS 重复的那套业务逻辑抽成共享内核，
顺手修掉已经因重复而产生的 2 个真实 bug——这是唯一值得做的结构性重构。
