# iOS 阅读器图片布局重构设计

## 目标

仅修改 iOS 客户端，在保留横向翻页、纵向瀑布流、双击与捏合缩放、图片下采样、内存缓存、请求合并、前后页预取、章节切换和阅读进度恢复的前提下，消除纵向阅读器中实际图片高度与页面展示高度不一致的问题。

## 根因

当前纵向页面存在多个布局尺寸来源：

- SwiftUI 页面高度使用 `DecodedImageAsset.displaySize`。
- UIKit 内部 `UIImageView` 高度使用下采样后的 `UIImage.size`。
- 图片加载前使用采样页面的中位宽高比或固定 `500pt`。
- UIKit 会先设置图片，SwiftUI 随后才通过回调更新页面高度。

因此，原图元数据与实际解码图片比例存在差异、预取未完成、页面比例变化或 SwiftUI/UIKit 更新时序不同时，图片会在错误高度的容器中短暂或持续显示。

## 设计原则

1. 实际展示图片的宽高比是唯一布局真值。
2. 可见加载和预取使用同一图片管线与同一缓存身份。
3. 页面状态使用稳定页面 ID，不用数组下标作为异步结果身份。
4. 布局状态只保存宽高比，不长期强持有所有 `UIImage`。
5. 占位高度可以估算，但真实图片只在精确布局就绪后显示。
6. 横向模式保留现有 viewport 内居中适配行为。

## 数据模型

`DecodedImageAsset` 增加由实际解码图片计算的只读布局比例：

```swift
var layoutAspectRatio: CGFloat {
    image.size.height / image.size.width
}
```

`displaySize` 继续用于原图元数据和诊断，不再用于阅读器布局。

纵向页面布局状态按稳定页面 ID 保存：

```swift
struct ReaderPageID: Hashable {
    let episodeID: String
    let pageID: String
}
```

布局缓存只保存 `layoutAspectRatio`，图片继续由 `ImageCache` 管理。

## 图片显示流程

1. 页面先使用已有精确比例、章节样本比例或默认比例绘制占位。
2. 可见加载或预取通过 `ImageCache.loadAsset` 获取同一 `DecodedImageAsset`。
3. 从 `asset.layoutAspectRatio` 更新页面精确高度。
4. `ZoomableImageView` 同时接收 `asset.image` 和相同比例。
5. 纵向模式在 `UIScrollView.bounds.height` 与 `bounds.width * ratio` 相符后显示图片。
6. 横向模式立即按 viewport 适配并居中。

## 组件边界

### `ImageDecoding`

- 创建解码图片。
- 处理 EXIF 方向。
- 暴露基于实际展示图片的 `layoutAspectRatio`。

### `ReaderVerticalImageLayout`

- 根据 viewport 宽度和精确或估算比例计算页面高度。
- 不接触 `UIImage`、网络或缓存。

### `ZoomingImageScrollView`

- 接收图片和明确的布局比例。
- 使用该比例计算 `UIImageView.frame`。
- 纵向模式等待外层高度匹配后显示图片。
- 保留缩放和居中行为。

### `ComicReaderView`

- 使用页面稳定 ID 保存精确比例。
- 预取结果和可见图片回调都写入同一比例缓存。
- 章节切换时清理本章布局状态并拒绝旧预取结果。

## 占位策略

优先级如下：

1. 当前页面已经解码得到的精确比例。
2. 当前章节已经加载页面的中位比例。
3. 默认比例 `1.5`。

占位状态可以调整高度；真实图片出现后不得再使用估算比例。

## 错误与取消

- 网络或解码失败时保留占位并允许现有可见加载重试。
- 预取失败不得阻塞阅读。
- URL、章节或 viewport 解码档位变化时取消旧可见任务。
- 旧章节预取结果通过预取 key 和稳定页面 ID 被丢弃。
- 缓存清理可以释放图片，但精确比例在当前阅读会话内保留。

## 测试

1. 验证布局比例来自实际 `UIImage`，而不是 `displaySize`。
2. 验证纵向 row 高度和 `UIImageView.frame.height` 使用同一比例。
3. 验证外层高度未匹配时纵向图片保持隐藏，匹配后显示。
4. 验证横向模式仍立即显示并居中。
5. 使用不同宽高比和 EXIF 方向图片覆盖解码路径。
6. 保留并运行现有阅读器、图片管线和进度测试。

## 非目标

- 不修改服务端接口。
- 不替换现有 UIKit 缩放实现。
- 不改变阅读模式、工具栏或进度持久化交互。
- 不增加磁盘图片元数据数据库。
