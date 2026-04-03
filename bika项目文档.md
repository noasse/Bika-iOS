# Bika-iOS 项目文档

## 项目概览

Bika-iOS 是一个使用 SwiftUI 构建的 iOS 漫画阅读应用。  
当前工程已从“功能堆叠阶段”进入“可持续维护阶段”，核心方向不是推倒重来，而是继续沿着以下原则做渐进式优化：

- 显式依赖注入
- 统一分页列表模式
- 收紧解码与错误边界
- 让失败路径可见、可测、可回归

截至 `2026-04-03`，工程已经通过：

- `build-for-testing`
- `unit`
- `ui-smoke`

## 当前代码结构

当前 `bika/` 下共有 `59` 个 Swift 文件，结构如下：

```text
bika/
├── bikaApp.swift
├── ContentView.swift
├── Models/
├── Network/
├── Support/
├── ViewModels/
├── Views/
└── Views/Helpers/
```

按目录划分：

- `Models`：数据模型、API 响应结构、解码策略
- `Network`：接口配置、端点定义、签名、客户端、错误类型
- `Support`：依赖容器、Mock 路由、导航状态、图片解码、测试辅助
- `ViewModels`：页面状态、异步加载、业务边界
- `Views`：页面本身与页面级组合
- `Views/Helpers`：通用视图、分页组件、图片加载、主题与持久化 manager

## 架构原则

### 1. 以 SwiftUI + `@Observable` 为主

工程整体仍然沿用 SwiftUI + `@Observable` 的方向。  
不是做完全的架构切换，而是在现有方向上把边界收紧。

### 2. View 负责布局与轻量编排

View 可以：

- 持有 ViewModel
- 绑定状态
- 响应点击、导航、弹窗
- 触发异步动作

View 不应该：

- 直接拼网络请求
- 直接操作 `UserDefaults.standard`
- 在 `body` 里扩散共享 manager 的业务调用
- 复制一整套分页状态机

### 3. 共享对象可以作为默认注入源，但不要在页面里横向扩散

允许这种方式：

```swift
init(client: any APIClientProtocol = APIClient.shared)
```

但不鼓励这种方式：

```swift
Task {
    let response = try await APIClient.shared.send(...)
}
```

区别在于：

- 前者便于测试替换
- 后者会让 View 同时承担 UI、依赖选择和业务执行

## 关键设计点

### 依赖注入与基础设施

依赖入口主要收敛在这些类型中：

- [AppDependencies.swift](bika/Support/AppDependencies.swift)
- [APIClient.swift](bika/Network/APIClient.swift)
- [KeyValueStore.swift](bika/Support/KeyValueStore.swift)
- [NavigationStateStore.swift](bika/Support/NavigationStateStore.swift)

目前的原则是：

- 保留 `AppDependencies.shared.configureForLaunch()` 作为启动装配点
- 所有页面和 ViewModel 优先依赖协议或注入参数
- `shared` 主要作为默认值或应用启动时的装配源

### 统一分页列表模式

这一轮最重要的结构收口是把“漫画结果列表”统一成一套模式。

核心类型：

- [ComicResultsViewModel.swift](bika/ViewModels/ComicResultsViewModel.swift)
- [PaginatedComicResultsView.swift](bika/Views/Helpers/PaginatedComicResultsView.swift)

当前已经复用到：

- 收藏列表
- 作者结果页
- 标签结果页
- 搜索结果页的 UI 壳
- 分类列表页也已部分与其对齐

统一后的公共行为包括：

- 加载态
- 空态
- 错误态
- 分页按钮
- 页码跳转
- 排序切换
- 返回定位恢复
- 上次页码恢复

后续新增漫画列表页时，默认先考虑能否复用这套模式。

### 详情页拆分

详情页已不再把所有内容塞在一个大文件里。

相关文件：

- [ComicDetailView.swift](bika/Views/ComicDetailView.swift)
- [ComicDetailSections.swift](bika/Views/ComicDetailSections.swift)

已拆分出的模块包括：

- 头部信息区
- 操作区
- 分类区
- 标签区
- 简介区
- 章节区
- 继续阅读区
- 评论入口
- 推荐区

这样做的意义：

- 详情页行为更清楚
- 局部回归更容易定位
- 未来继续扩展时不会再把一个文件越堆越大

### 解码与错误边界

模型层当前遵循：

- 关键字段严格
- 非关键展示字段宽容

典型例子见：

- [CommentModels.swift](bika/Models/CommentModels.swift)
- [CommonModels.swift](bika/Models/CommonModels.swift)

当前已经明确的规则：

- `Comment.id`、评论分页结构等关键字段必须显式失败
- 可选展示字段可以降级为 `nil`
- `Media.imageURL` 会统一规范化 `static/` 前缀
- 用户动作失败不能静默吞掉
- 后台辅助加载失败可以降级，但要有明确边界

### 失败可见策略

本项目当前不再鼓励“看起来没报错，其实悄悄失败了”的处理。

现在的目标是：

- 加载失败时，要么显示错误态，要么至少保留旧状态不误导用户
- 点赞、收藏、评论、回复等动作失败，要有可见反馈
- 推荐区这类辅助信息失败可以降级，但不影响主流程

这类策略已经体现在：

- 评论页
- 子评论页
- 详情页推荐区
- 阅读器页面加载失败
- 分类页、个人页、排行榜页等页面的加载边界

## 当前重要模块

### Network

关键文件：

- [APIConfig.swift](bika/Network/APIConfig.swift)
- [APIEndpoints.swift](bika/Network/APIEndpoints.swift)
- [APIClient.swift](bika/Network/APIClient.swift)
- [APIError.swift](bika/Network/APIError.swift)

职责：

- 定义接口、请求头、签名和错误模型
- 统一处理鉴权、业务错误和解码错误

### Support

关键文件：

- [AppDependencies.swift](bika/Support/AppDependencies.swift)
- [MockURLProtocol.swift](bika/Support/MockURLProtocol.swift)
- [SmokeFixtureRouter.swift](bika/Support/SmokeFixtureRouter.swift)
- [NavigationStateStore.swift](bika/Support/NavigationStateStore.swift)
- [ImageDecoding.swift](bika/Support/ImageDecoding.swift)

职责：

- 统一启动依赖
- 提供 UI 测试与单测的 mock 环境
- 管理列表/排行榜的恢复状态
- 处理图片解码与测试图片加载

### ViewModels

当前更重要的 ViewModel 包括：

- `AuthViewModel`
- `ComicListViewModel`
- `ComicResultsViewModel`
- `ComicDetailViewModel`
- `CommentsViewModel`
- `ReaderViewModel`
- `SettingsViewModel`

职责边界：

- 维护页面状态
- 发起异步动作
- 收口失败路径
- 提供可测试的业务行为

### Views

当前更重要的页面包括：

- `CategoriesView`
- `ComicListView`
- `SearchView`
- `LeaderboardView`
- `ComicDetailView`
- `ComicReaderView`
- `CommentsView`
- `FavouritesView`
- `ProfileView`
- `SettingsView`

其中：

- 列表页优先走统一分页模式
- 详情页通过 section 拆分
- 阅读器单独处理进度恢复与图片加载

## 测试与质量基线

测试说明详见 [TESTING.md](TESTING.md)。

当前质量基线是：

- PR 至少通过 `unit`
- 改动主链路时通过 `ui-smoke`
- 新增分页列表优先复用共享抽象
- 新增网络请求通过可注入 client 进入
- 新增模型解码时写清楚关键字段与降级字段

## 后续维护建议

### 推荐继续坚持的方向

- 继续复用统一分页列表模式
- 新代码继续走显式依赖注入
- 失败路径继续保持“可见、可测、可定位”
- 大页面继续拆成小 section 或独立子视图

### 不建议回退的做法

- 在 View 中直接写 `APIClient.shared.send(...)`
- 在 View 中直接写 `UserDefaults.standard`
- 新增一套独立分页状态机
- 为了“容错”把关键字段全部 `try?`
- 用户动作失败后静默吞错

## 文档索引

- GitHub 首页说明：`README.md`
- 测试说明：[TESTING.md](TESTING.md)
- 本文件：项目架构、边界与维护约定
