# iOS 阅读器深度分析

- 日期：2026-08-07
- 分支：`refactor/shared-domain-core`
- 基线：`f7fea74`，166 单测全绿
- 范围：仅 iOS 阅读器（`ComicReaderView` / `ZoomableImageView` / `ReaderViewModel` / 图片预取链路），不含 macOS

---

## 零、先看这个信号

阅读器这块被反复修：

```
6e679f7 refactor: rewrite ZoomableImageView using UIScrollView instead of SwiftUI gestures
460d3d8 Fix iOS vertical reader image height
966412b fix: harden account state, readers, and image pipelines
72114b7 fix: stabilize iOS reader image layout
efc13dd fix: keep reader toolbar responsive after initial layout
```

五次针对同一区域的修复，外加一次被放弃的「回退到 1.2.0」尝试。
**反复修不好 = 设计问题，不是 bug 问题。** 下面是根因。

---

## 一、致命问题：预取 100% 落空，每张图都下载并解码两次

这是阅读器最严重的问题，而且**默认模式（横向翻页）下必然发生**。

### 链路

预取的解码目标（`ComicReaderView.swift:417`）：

```swift
private func imagePrefetchTarget() -> ImageDecodeTarget? {
    switch viewModel.readerMode {
    case .horizontal:
        return .fit(viewportSize)          // ← viewportSize 来自 ZStack 的 onGeometryChange
    case .vertical:
        return .fitWidth(viewportSize.width)
    }
}
```

显示的解码目标（`ZoomableImageView.swift:383`）：

```swift
private func decodeTarget(in scrollView: ZoomingImageScrollView) -> ImageDecodeTarget {
    switch parent.sizing {
    case .viewport:
        return .fit(scrollView.bounds.size)   // ← UIScrollView 的实际 bounds
    case .fitWidth(let width):
        return .fitWidth(width)
    }
}
```

两个尺寸来源不同：

| | 来源 | 是否含安全区 |
|---|---|---|
| `viewportSize` | `ZStack` 的 `.onGeometryChange`（`ComicReaderView.swift:103`） | **否**——`fullScreenCover` 内容默认被安全区内缩，ZStack 本身没有 `.ignoresSafeArea()`；`Color.black.ignoresSafeArea()` 只放大那个 Color，不改变 ZStack 自身尺寸 |
| `scrollView.bounds` | `horizontalReader` 的 `ScrollView` 带 `.ignoresSafeArea()`（`:236`），cell 高度 = 全屏高 | **是** |

### 缓存键不做分桶，差 1pt 就是两条记录

`ImageDecoding.swift:11`：

```swift
case .fit(let size):
    return "fit-\(Self.rounded(size.width))x\(Self.rounded(size.height))"   // rounded = Int(value.rounded())
```

`ImageCache.cacheIdentity` 直接把这个字符串拼进 key。**没有任何容差或分桶。**

以 iPhone 17 竖屏为例（402×874pt，顶部安全区 59、底部 34）：

- 预取 key：`fit-402x781`
- 显示 key：`fit-402x874`

**两条完全不同的缓存记录。**

### 后果

1. 预取的图**一张都用不上**，显示时全部重新走网络 + 重新解码。
2. 预取产物仍然占着 `NSCache` 的成本额度，**挤掉真正有用的缓存条目**（`ImageCacheCostTracker` 按解码后像素计费）。
3. 流量、CPU、内存全部翻倍。用户感知就是"明明有预取，翻页还是卡"。

竖向模式同理：`viewportSize.width`（安全区宽）vs `verticalReader` 里 `GeometryReader` 的宽度——
后者因为 `.ignoresSafeArea()`（`:276`）拿到的是全屏宽。竖屏时左右安全区为 0，两者相等，所以**竖向模式在竖屏下侥幸没事**；
**一旦横屏（刘海侧边距非 0）就同样全部落空**。

而 `readerMode` 默认值是 `.horizontal`（`ReaderViewModel.swift:57`）——**默认路径就是全миss 的那条**。

### 为什么 166 个测试没抓到

我查了：**没有任何测试断言"预取目标 == 显示目标"**。

`ImagePipelineTests` 测的是「给预取器一批请求，它会正确预取」，以及「显示路径能正确加载」——
两半各自都对，**没人测它们对不对得上**。这正是集成缺陷的典型盲区。

---

## 二、横向模式下，预取回调白白触发整棵视图重渲染

`onImageAspectRatio` 只在竖向模式传入（`:254`），但预取结果对**两种模式**都回灌：

```swift
for (pageID, aspectRatio) in prefetchedAspectRatios {
    updateImageAspectRatio(aspectRatio, for: pageID)   // :386
}
```

`updateImageAspectRatio` 写 `@State imageAspectRatios`。而 `imageAspectRatios` 只被 `pageHeight(for:)` 读，
`pageHeight` **只在竖向模式用**。

所以横向模式下：每预取成功一张图 → 改一次 `@State` → **整个 `ComicReaderView.body` 重新求值** → 收益为零。
一次预取 5 张 = 5 次无谓全量重渲染。

---

## 三、竖向模式的布局反馈环，以及"图片先隐藏再显示"的补丁

竖向模式存在一条**闭环**：

```
pageHeight(imageAspectRatios[pageID])
      ↓ 决定
.frame(height:)  →  UIScrollView bounds 变化
      ↓ 触发
layoutSubviews → onBoundsSizeChange → loadImageIfNeeded
      ↓ 加载完成
display() → onImageAspectRatio → updateImageAspectRatio
      ↓ 写回
imageAspectRatios   ←── 回到起点
```

这个环靠 `loadImageIfNeeded` 里的 `guard identity != loadedIdentity`（`ZoomableImageView.swift:259`）刹车——
因为 `.fitWidth` 的 identity 不含高度，所以高度变化不会重新触发加载，环才收敛。
**收敛依赖于"解码目标恰好与高度无关"这个隐含前提**，一旦有人把竖向模式改成 `.fit(size)` 就会变成死循环。

为了掩盖环内的中间态，加了 `waitsForFitWidthBounds` 机制（`ZoomableImageView.swift:56, 131`）：

```swift
readerImageView.isHidden = image != nil && waitsForFitWidthBounds        // 加载完先藏起来
...
readerImageView.isHidden = waitsForFitWidthBounds
    && abs(boundsSize.height - fitHeight) >= 1                            // 高度对上了才显示
```

也就是说：**图片加载完成后先被主动隐藏，等 SwiftUI 把 frame 高度改到与图片比例吻合（误差 <1pt）才显形。**
正常情况下多花一帧；一旦 SwiftUI 侧高度与 UIKit 侧算出的 `fitHeight` 因为任何原因差满 1pt，
**这一页就永久空白**——而且没有任何日志或兜底。

这是典型的"用补丁掩盖架构问题"：环本身没拆，只是把环内的丑陋状态藏起来。

---

## 四、估算宽高比导致滚动位置漂移

竖向模式对还没量到真实比例的页，用「前 3 页的中位数」估算高度（`:287-325`）：

```swift
guard sampledPageIDs.count < 3, !sampledPageIDs.contains(pageID) else { return }
```

问题：`estimatedAspectRatio` 是**渐进变化**的。第 1 个样本到达 → 估算值 = 它本身；
第 2、3 个样本到达 → 中位数改变 → **所有未量测页的高度同时改变** → 用户脚下的内容整体抽动。

叠加 `resetImageLayoutState()` 在每次换章时清空（`:157`），**每换一章都要重新经历一次抖动**。

漫画单话内部页面比例本来就参差（跨页、条漫、作者后记），3 个样本的中位数对后面 100 页毫无代表性。

---

## 五、死状态

```swift
var currentPageIndex = 0        // ReaderViewModel.swift:8
```

**全项目只有这一处**（声明处）。从未被写入，从未被读取。
而 View 自己维护了 `@State private var currentPage`（`ComicReaderView.swift:14`）——
两个"当前页"，ViewModel 那个是死的。任何人看 ViewModel 都会以为它是权威来源。

```swift
private var paginationPage = 0
private var paginationTotalPages = 1
```

写了 10 次，**一次都没读过**。还为此在 `applyLoadFailure` 上挂了两个纯装饰用的参数（`:222-223`）。

---

## 六、`viewportSize` 是单点失效，工具栏点击失灵的根因还在

`handleTap`（`:203`）：

```swift
let screenWidth = max(viewportSize.width, 1)
let center = screenWidth / 2
let margin = screenWidth * 0.3
if location.x > center - margin && location.x < center + margin {
```

如果 `viewportSize` 还是 `.zero`，`screenWidth` 被兜底成 **1**，判定区间变成 x ∈ (0.2, 0.8) 点——
**任何点击都不可能命中，工具栏彻底点不出来，且完全静默**。

`efc13dd` 修的正是这个：原来比较 `oldSize` vs `newSize`，导致 `viewportSize` 可能一直没被赋值。
**但修的是触发条件，不是"兜底值把功能静默废掉"这个设计**。`max(viewportSize.width, 1)` 还在那里。

同一个 `viewportSize` 同时喂三件不相干的事：点击热区、预取解码目标、预取调度。
任何一处让它变脏/变零，三件事以三种不同的静默方式坏掉。

附带一条：`.statusBar(hidden: !viewModel.showToolbar)` 会改变安全区 →
`onGeometryChange` 触发 → `imagePrefetchKey = nil` → **每次开关工具栏都重跑一遍预取**。

---

## 七、竖向模式里每页套一个可缩放 UIScrollView

竖向模式下每一页都是一个独立的 `ZoomingImageScrollView`（带双击缩放、`maximumZoomScale = 4`），
嵌在 SwiftUI 的纵向 `ScrollView` 里。

- 未缩放时 `contentSize == bounds`，手势穿透给外层，正常。
- **一旦某页被双击放大**，该页的 UIScrollView 开始吃掉纵向 pan 手势 →
  **用户在这一页上划不动整章，必须先双击缩回去**。没有任何提示。

条漫式的竖向阅读本来就不该给每页独立缩放。这是把横向模式的组件直接复用到竖向的代价。

---

## 八、根因：一个没人负责的隐式状态机

`ComicReaderView` 持有 **9 个 `@State`**：

```
currentPage, scrollPosition          ← 两份"当前位置"
hasJumpedToStart                     ← 一次性闩锁
imageAspectRatios, sampledPageIDs,
sampledAspectRatios, estimatedAspectRatio   ← 四份布局状态
imagePrefetchTask, imagePrefetchKey  ← 两份预取状态
viewportSize                         ← 喂三个不相干消费者
```

外加 `ReaderViewModel` 的 `showToolbar` / `readerMode` / `currentPageIndex`(死)。

由 **7 个 `.task` / `.onChange` / `.onDisappear` / `.onGeometryChange`** 回调交叉修改，
执行顺序取决于 SwiftUI 的更新时机。没有任何一处集中表达"这些状态之间必须满足什么不变量"。

**所以每次修一个症状，就在别处碰坏一个**——这就是那 5 次修复的由来。

---

## 九、建议方案

核心思路：**把"视口 → 解码目标"变成唯一事实来源，把散落的布局状态收进一个可测的类型。**

### 阶段 1：修预取失效（收益最大，改动最小）

抽出一个纯函数类型，横向/竖向、预取/显示**共用同一个解码目标**：

```swift
nonisolated struct ReaderDecodeTargetResolver {
    static func target(mode: ReaderMode, contentSize: CGSize) -> ImageDecodeTarget?
}
```

关键是让预取和显示都从**同一个尺寸来源**取值——统一用 `ZoomableImageView` 实际所处容器的尺寸
（即已经 `ignoresSafeArea` 之后的 cell 尺寸），而不是 ZStack 的安全区尺寸。

配套：给 `ImageDecodeTarget.cacheKey` 加**分桶**（比如按 8pt 取整），
让 ±几 pt 的抖动不再产生新缓存键。这一条单独就能显著减少重复解码。

**必须补的测试**（当前完全缺失）：断言同一页在 `.readerPrefetch` 和 `.readerVisible` 两个 purpose 下
产生**相同的 `cacheIdentity`**。这个测试一旦存在，本类 bug 不会再复发。

### 阶段 2：拆掉竖向布局反馈环

让"页高"由**已解码资产的真实比例**单向决定，不再从 UIKit 回灌 SwiftUI：
预取阶段就把比例写入一个 `ReaderPageLayoutStore`，显示层只读不写。
环拆掉之后，`waitsForFitWidthBounds` 这套隐藏/显形补丁可以整体删除。

### 阶段 3：收拢状态

用一个 `@Observable ReaderLayoutModel` 收编 9 个 `@State` 中的 7 个
（位置、布局、预取），只留真正属于视图的。让不变量集中、可单测。

同时删掉 `currentPageIndex`、`paginationPage`、`paginationTotalPages` 三处死状态
及 `applyLoadFailure` 的两个装饰参数。

### 阶段 4：竖向模式换掉可缩放容器

竖向模式改用不带 zoom 的轻量图片视图，消除嵌套滚动手势冲突；
缩放能力保留在横向模式。

### 阶段 5：`viewportSize` 失效不再静默

`handleTap` 在视口无效时应当**直接不处理**（或退化为"整屏可点"），
而不是用 `max(..., 1)` 兜出一个必然不命中的热区。

---

## 十、怎么在真机上确认问题一

项目里已经有现成的验证工具（`feat: export image diagnostics from settings`）：
诊断事件记录了 `purpose`（`readerPrefetch` / `readerVisible`）和 `decodeTarget` 字符串。

**操作**：横向模式翻几页 → 设置页导出诊断 → 对比同一张 URL 的两条记录。
如果 `decodeTarget` 一个是 `fit-402x781`、另一个是 `fit-402x874`，问题一即得到实测确认。

> 说明：上面关于安全区的推导来自代码与 SwiftUI 布局规则，尚未在运行时实测。
> 结论方向我有把握，但**具体差值以导出的诊断为准**。

---

## 十一、一句话总结

阅读器的问题不是"某个地方写错了"，而是**同一个视口尺寸被三个消费者以三种口径使用，
且预取与显示各自取了不同的来源**——默认横向模式下预取全部作废、每张图下载解码两次；
外加一条 UIKit↔SwiftUI 的布局反馈环，用"先隐藏图片"的补丁掩盖着。
先修预取（阶段 1），投入最小、体感提升最直接。
