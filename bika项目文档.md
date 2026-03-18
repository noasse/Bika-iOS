# Bika — PicACG 漫画阅读器 iOS 项目文档

> SwiftUI + async/await · Xcode 26.3 · iOS 18.0+
> 共 **46 个 Swift 文件**，MVVM 架构

---

## 目录结构总览

```
bika/
├── bikaApp.swift                    # App 入口
├── ContentView.swift                # 根视图（登录/主界面切换）
├── Models/          (6 文件)        # 数据模型
├── Network/         (5 文件)        # 网络层
├── ViewModels/      (8 文件)        # 视图模型
├── Views/           (14 文件)       # 页面视图
└── Views/Helpers/   (7 文件)        # 通用组件 & 管理器
```

---

## 根目录（2 文件）

### `bikaApp.swift`
App 入口，创建 WindowGroup 并注入环境对象。

| 成员 | 说明 |
|------|------|
| `@State var authVM` | AuthViewModel 实例 |
| `body: some Scene` | 创建 WindowGroup → ContentView，注入 authVM 环境 + ThemeManager 主题色 |

### `ContentView.swift`
根据登录状态切换视图。

| 成员 | 说明 |
|------|------|
| `body: some View` | 优先检查 `isAuthenticated`（有 token 则瞬间进入主页），其次 `isCheckingToken` 显示 splash，最后显示 `LoginView` |
| `.task` | 启动时调用 `authVM.checkToken()` 检查本地 token |

**启动流程**：有持久化 token → 立即显示 MainTabView（< 1 秒），后台异步验证 token 有效性；token 无效时才回退到登录页。

---

## Models/（6 文件）

### `APIResponse.swift`
通用 API 响应包装。

| 类型 | 说明 |
|------|------|
| `APIResponse<T>` | 通用响应：`code` + `message` + `data: T?` |
| `PaginatedResponse<T>` | 分页响应：`docs: [T]` + `total` + `limit` + `page` + `pages` |
| `EmptyData` | 空响应占位（用于 POST 不返回数据的端点） |

### `AuthModels.swift`
认证相关模型。

| 类型 | 说明 |
|------|------|
| `SignInRequest` | 登录请求体：`email` + `password` |
| `SignInData` | 登录成功返回的 `token` |
| `RegisterRequest` | 注册请求体：邮箱、密码、昵称、生日、性别、安全问答 |

### `CommonModels.swift`
全局复用的基础模型。

| 类型 | 字段 / 方法 | 说明 |
|------|------------|------|
| `Media` | `originalName`, `path`, `fileServer` | 图片资源 |
| | `var imageURL: URL?` | 计算属性，拼接完整图片 URL |
| `Creator` | `id`, `name?`, `level`, `exp`, `avatar`, `slogan`, `title` 等 | 用户/创建者信息（name 可选，兼容已删除用户） |

### `ComicModels.swift`
漫画核心模型。

| 类型 | 说明 |
|------|------|
| `Category` | 分类：id, title, description, thumb, isWeb, active, link |
| `CategoriesData` | 分类列表包装 |
| `Comic` | 漫画列表项：id, title, author, totalViews, totalLikes, pagesCount, epsCount, finished, categories, thumb |
| `ComicsData` | 漫画分页包装 |
| `ComicDetail` | 漫画详情：含 description, creator, tags, isFavourite, isLiked, allowComment 等 |
| `ComicDetailData` | 详情包装 |
| `Episode` | 章节：id, title, order, updated_at |
| `EpisodesData` | 章节分页包装 |
| `ComicPage` | 单页图片：id + media |
| `ComicPagesData` | 页面分页包装 + EpisodeRef |
| `EpisodeRef` | 章节引用（id + title） |
| `SearchRequest` | 搜索请求：keyword, sort, categories |
| `LikeActionData` | 点赞结果：action ("like"/"unlike") |
| `LeaderboardData` | 排行榜包装：`comics: [Comic]` |
| `RecommendedData` | 推荐包装：`comics: [Comic]`，自定义解码器逐个解析 comic，跳过解码失败的条目 |

### `CommentModels.swift`
评论模型。

| 类型 | 说明 |
|------|------|
| `Comment` | 评论：id, content?, user(`_user`), comic(`_comic`), isTop, created_at, likesCount, commentsCount, isLiked（自定义解码器，所有字段 `try?` 容错） |
| `CommentsData` | 自定义解码器：评论分页 + `topComments` 置顶数组（不使用 PaginatedResponse，手动解析嵌套 comments 对象） |
| `ChildCommentsData` | 自定义解码器：子评论分页 |
| `PostCommentRequest` | 发评论请求体：`content` |

### `UserModels.swift`
用户模型。

| 类型 | 说明 |
|------|------|
| `UserProfile` | 用户完整信息：email, name, birthday, avatar, isPunched, role, level, exp 等 |
| `UserProfileData` | 用户信息包装 |
| `PunchInData` / `PunchInResult` | 打卡结果 |
| `FavouriteData` | 收藏分页包装 |
| `UpdatePasswordRequest` | 改密请求：old_password + new_password |
| `UpdateSloganRequest` | 改签名请求：slogan |

---

## Network/（5 文件）

### `APIConfig.swift`
API 静态配置常量。

| 成员 | 说明 |
|------|------|
| `APIConfig.baseURL` | API 基础地址 |
| `APIConfig.apiKey` / `secretKey` | HMAC 签名用密钥 |
| `APIConfig.nonce` / `channel` / `version` / `buildVersion` / `platform` / `userAgent` | 请求头参数 |
| `enum SortMode` | 排序模式：defaultSort(ua)、newest(dd)、oldest(da)、liked(ld)、views(vd) |
| `enum LeaderboardType` | 排行榜类型：hour24、day7、day30 |
| `enum ImageQuality` | 图片质量：original、low、medium、high |

### `APISignature.swift`
HMAC-SHA256 请求签名。

| 方法 | 说明 |
|------|------|
| `static func sign(path:method:timestamp:nonce:) -> String` | 生成请求签名字符串 |

### `APIEndpoints.swift`
所有 API 端点定义，使用泛型 `APIEndpoint<Response>` + 类型约束扩展。

| 端点 | 方法 | 路径 |
|------|------|------|
| `signIn(email:password:)` | POST | `auth/sign-in` |
| `register(_:)` | POST | `auth/register` |
| `punchIn()` | POST | `users/punch-in` |
| `setSlogan(_:)` | PUT | `users/profile` |
| `changePassword(old:new:)` | PUT | `users/password` |
| `myProfile()` | GET | `users/profile` |
| `categories()` | GET | `categories` |
| `comics(category:page:sort:)` | GET | `comics?page=&c=&s=` |
| `search(keyword:page:sort:categories:)` | POST | `comics/advanced-search?page=` |
| `favourites(page:sort:)` | GET | `users/favourite?s=&page=` |
| `comicDetail(id:)` | GET | `comics/{id}` |
| `episodes(comicId:page:)` | GET | `comics/{id}/eps?page=` |
| `comicPages(comicId:epsOrder:page:)` | GET | `comics/{id}/order/{order}/pages?page=` |
| `likeComic(id:)` | POST | `comics/{id}/like` |
| `likeComment(id:)` | POST | `comments/{id}/like` |
| `favouriteComic(id:)` | POST | `comics/{id}/favourite` |
| `comments(comicId:page:)` | GET | `comics/{id}/comments?page=` |
| `childComments(commentId:page:)` | GET | `comments/{id}/childrens?page=` |
| `postComment(comicId:content:)` | POST | `comics/{id}/comments` |
| `postChildComment(commentId:content:)` | POST | `comments/{id}/childrens` |
| `leaderboard(type:)` | GET | `comics/leaderboard?tt=&ct=VC` |
| `recommended(comicId:)` | GET | `comics/{id}/recommendation` |

### `APIClient.swift`
网络请求客户端。

| 类型 / 方法 | 说明 |
|------------|------|
| `actor TokenStore` | 线程安全的 token 存储，**持久化到 UserDefaults**（`com.bika.authToken`），启动时自动恢复 |
| → `setToken(_:)` | 存储 token（内存 + UserDefaults） |
| → `getToken()` | 获取 token |
| → `clear()` | 清除 token（内存 + UserDefaults） |
| `protocol APIClientProtocol` | 定义 `send<T>` 接口 |
| `class APIClient` | 单例 `shared`，基于 URLSession |
| → `send<T>(_:)` | 构建 13 个必需请求头 + HMAC 签名 → 发送请求 → 解码响应 |
| → `signIn(email:password:)` | 登录并自动存储 token |

### `APIError.swift`
统一错误类型。

| 枚举值 | 说明 |
|--------|------|
| `invalidURL` | URL 无效 |
| `httpError(statusCode, data)` | HTTP 非 200 |
| `apiError(code, message)` | 服务端业务错误 |
| `unauthorized` | 未授权 |
| `decodingError(Error)` | JSON 解码失败 |
| `networkError(Error)` | 网络连接失败 |
| `noToken` | 无登录 token |

---

## ViewModels/（8 文件）

### `AuthViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `var isAuthenticated: Bool` | 登录状态 |
| `var isLoading: Bool` | 登录请求加载中 |
| `var isCheckingToken: Bool` | 启动时 token 检查中（初始 true） |
| `var errorMessage: String?` | 错误信息 |
| `func login(email:password:)` | 调用 signIn API，成功后设置 isAuthenticated |
| `func logout()` | 清除 token，设置 isAuthenticated = false |
| `func checkToken()` | 有 token → **立即** `isAuthenticated = true` + `isCheckingToken = false`（瞬间进入主页），后台验证有效性；无效才回退 |

### `CategoriesViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `var categories: [Category]` | 分类列表 |
| `func loadCategories()` | 获取分类（排除 isWeb 类型） |

### `ComicListViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `let category: String` | 分类名 |
| `var comics, sortMode, currentPage, totalPages` | 列表状态 |
| `func loadFirstPage()` | 首次加载 |
| `func loadPage(_:)` | 加载指定页 |
| `func nextPage()` / `prevPage()` | 翻页 |
| `func changeSort(_:)` | 切换排序并重新加载 |
| `func goToLastVisited()` | 跳回上次浏览页 |
| `func persistPage()` | 保存当前页到 UserDefaults |

### `ComicDetailViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `let comicId: String` | 漫画 ID |
| `var detail: ComicDetail?` | 漫画详情 |
| `var episodes: [Episode]` | 全部章节（自动分页加载 + 排序） |
| `var recommended: [Comic]` | 推荐漫画 |
| `var recommendedError: String?` | 推荐加载失败的错误信息（UI 可见） |
| `func load()` | 加载详情 → 章节 → 推荐 |
| `func toggleLike()` | 点赞/取消点赞 |
| `func toggleFavourite()` | 收藏/取消收藏 |
| `func loadRecommended()` | 获取相关推荐（public，支持重试） |

### `ReaderViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `let comicId, episodes` | 漫画 ID 和章节列表 |
| `var currentEpisodeIndex: Int` | 当前章节索引 |
| `var pages: [ComicPage]` | 当前章节所有页面 |
| `var currentPageIndex: Int` | 当前页码 |
| `var readerMode: ReaderMode` | 阅读模式（horizontal/vertical），UserDefaults 持久化 |
| `var showToolbar: Bool` | 工具栏显示状态 |
| `func loadPages()` | 分页加载当前章节全部页面 |
| `func goToEpisode(_:)` | 跳转到指定章节 |
| `func nextEpisode()` / `previousEpisode()` | 上一章/下一章 |
| `func toggleToolbar()` | 切换工具栏 |
| `func setReaderMode(_:)` | 切换阅读模式并持久化 |

### `CommentsViewModel.swift`
包含两个 ViewModel。

**CommentsViewModel（漫画评论）**

| 属性 / 方法 | 说明 |
|------------|------|
| `let comicId: String` | 漫画 ID |
| `var comments, topComments` | 普通评论 + 置顶评论 |
| `var commentText: String` | 输入框内容 |
| `var errorMessage: String?` | 加载失败时的错误信息 |
| `func loadPage(_:)` | 加载评论页（第 1 页包含 topComments） |
| `func postComment()` | 发表评论后刷新第 1 页 |
| `func likeComment(id:)` | 点赞评论后刷新当前页 |

**ChildCommentsViewModel（子评论/回复）**

| 属性 / 方法 | 说明 |
|------------|------|
| `let commentId: String` | 父评论 ID |
| `var comments` | 子评论列表 |
| `var replyText: String` | 回复输入框内容 |
| `func loadPage(_:)` | 加载子评论页 |
| `func postReply()` | 发表回复 |
| `func likeComment(id:)` | 点赞子评论 |

### `LeaderboardViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `var selectedType: LeaderboardType` | 当前排行榜类型 |
| `var comics: [Comic]` | 排行榜漫画列表 |
| `func load()` | 加载当前类型排行榜 |
| `func switchType(_:)` | 切换类型并重新加载 |

### `SearchViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `var keyword: String` | 搜索关键词 |
| `var comics, sortMode, currentPage, totalPages` | 结果状态 |
| `func search()` | 执行搜索 |
| `func loadPage(_:)` | 加载指定页 |
| `func changeSort(_:)` | 切换排序 |
| `func reset()` | 重置搜索状态 |
| `func persistPage()` | 保存当前页 |

### `ProfileViewModel.swift`

| 属性 / 方法 | 说明 |
|------------|------|
| `var profile: UserProfile?` | 用户资料 |
| `func loadProfile()` | 获取当前用户资料 |
| `func punchIn()` | 每日打卡并刷新 |
| `func updateSlogan(_:)` | 更新签名并刷新 |

---

## Views/（14 文件）

### `LoginView.swift`
登录页。邮箱/密码输入框 + 登录按钮，显示加载状态和错误信息。

### `MainTabView.swift`
主标签页。4 个 Tab，每个包裹 `NavigationStack`：

| Tab | 图标 | 内容 |
|-----|------|------|
| 分类 | folder | `CategoriesView` |
| 排行榜 | trophy | `LeaderboardView` |
| 搜索 | magnifyingglass | `SearchView` |
| 我的 | person | `ProfileView` |

### `CategoriesView.swift`
分类网格页。`LazyVGrid` 展示分类封面 + 标题，点击进入 `ComicListView`。

### `ComicListView.swift`
分类漫画列表。顶部排序栏 + `LazyVStack` 漫画卡片 + 底部翻页按钮 + 工具栏页码跳转。

附带 `SortMode.displayName` 扩展（默认/最新/最旧/最多爱心/最多观看）。

### `ComicCardView.swift`
漫画卡片组件。左侧封面（点击预览大图） + 右侧标题/作者/统计/分类。

附带 `ImagePreviewOverlay` 修改器（全屏图片预览 + 缩放动画）和 `.imagePreviewSheet(url:)` 扩展。

### `ComicDetailView.swift`
漫画详情页，从上到下：

1. 封面 + 元信息（标题/作者/汉化组/统计）
2. 操作按钮（喜欢/收藏）
3. 分类标签（点击进入分类列表，**目标式 NavigationLink**）
4. 标签（点击搜索，**目标式 NavigationLink**）
5. 简介
6. 章节网格（点击进入阅读器）
7. **继续阅读按钮**（从 ReadingProgressManager 读取进度）
8. **评论入口**（NavigationLink → CommentsView）
9. **相关推荐**（横滚封面卡片，加载失败时显示错误 + 重试按钮）

所有内部导航均使用**目标式 NavigationLink**（`NavigationLink { Destination() } label: { ... }`），确保在任意 NavigationStack 层级中正确跳转。

打开阅读器时自动记录阅读历史（`ReadingHistoryManager.shared.record()`）。

附带 `AuthorSearchResultsView` 和 `TagSearchResultsView`（作者/标签搜索结果页，含排序和翻页）。

### `ComicReaderView.swift`
漫画阅读器（fullScreenCover 弹出）。

| 组件 | 说明 |
|------|------|
| `ZoomableImageView` | 可缩放图片组件：双指缩放（1x–4x）+ 双击切换 1x/2x，`simultaneousGesture` 不阻塞滑动 |
| `horizontalReader` | `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` 翻页模式，`ScrollViewReader` 支持跳转，`.onScrollGeometryChange` 追踪当前页码 |
| `verticalReader` | `ScrollView(.vertical)` 滚动模式，`.onAppear` 追踪当前页码 |
| `toolbarOverlay` | 顶栏（关闭/章节标题/页码）+ 底栏（上一章/模式切换/下一章） |
| `saveProgress()` | 关闭时保存阅读进度到 ReadingProgressManager |
| iOS 原生滚动条 | `.scrollIndicators(.automatic)` 系统原生滚动指示器 |

**继续阅读恢复机制**：
- 页面加载采用分批加载（while 循环分页 API），每批加载后检查 `pages.count > startPageIndex`
- 满足条件后通过 `ScrollViewReader.proxy.scrollTo()` 跳转到目标页
- 不等待所有页面加载完毕，首批包含目标页即跳转

### `CommentsView.swift`
评论列表页。

| 组件 | 说明 |
|------|------|
| 置顶评论区 | topComments 优先显示，带「置顶评论」标题 |
| 普通评论列表 | LazyVStack + CommentCardView |
| 错误状态 | 显示错误信息 + 重试按钮（API 失败时） |
| 空状态 | 「暂无评论」提示 |
| 底部输入栏 | TextField + 发送按钮，safeArea 固定 |
| 翻页按钮 | 滚动到底部时出现 |
| 导航 | 点击评论 → push `ChildCommentsView`（`.navigationDestination(item:)`） |
| 用户信息 | 点击头像 → `UserProfileOverlay` 弹窗显示用户信息 |

### `ChildCommentsView.swift`
子评论（回复）页。

| 组件 | 说明 |
|------|------|
| 父评论 | 顶部展示原评论 |
| 回复列表 | LazyVStack + CommentCardView（隐藏回复数） |
| 回复输入栏 | 底部固定 TextField + 发送按钮 |
| 翻页按钮 | 滚动到底部时出现 |
| 用户信息 | 点击头像 → UserProfileOverlay |

### `LeaderboardView.swift`
排行榜页。顶部 `Picker`（24 小时/7 天/30 天），下方排名列表（带序号 + 漫画卡片）。

### `SearchView.swift`
搜索页。顶部搜索栏 + 排序选项 + 搜索结果列表 + 翻页。无搜索时显示快捷分类网格。

### `FavouritesView.swift`
收藏页。排序栏（数据加载后显示） + 漫画卡片列表 + 翻页按钮 + 页码跳转工具栏。使用**目标式 NavigationLink** 打开 ComicDetailView。

### `ReadingHistoryView.swift`
阅读历史页。

| 组件 | 说明 |
|------|------|
| 历史卡片 | 封面（60×84）+ 标题 + 作者 + 相对时间 |
| 导航 | 点击卡片 → push `ComicDetailView` |
| 清空 | 工具栏「清空」按钮 + 确认弹窗 |
| 空状态 | 「暂无阅读记录」提示 |
| `formatDate(_:)` | Date → 相对时间（刚刚/X分钟前/X小时前/昨天/日期） |

### `ProfileView.swift`
个人中心页。

| 区域 | 内容 |
|------|------|
| 用户卡片 | 头像 + 昵称 + 头衔 + 等级/经验 + 签名 |
| 打卡按钮 | 每日打卡（已打卡时禁用） |
| 菜单 | 我的收藏 → FavouritesView / 阅读记录 → ReadingHistoryView / 编辑签名 → Alert / 设置 → SettingsView |
| 退出登录 | 调用 authVM.logout() |

### `SettingsView.swift`
设置页。

| 区域 | 说明 |
|------|------|
| 主题模式 | 系统/浅色/深色 三选一 |
| 图片质量 | original/low/medium/high |
| 屏蔽分类 | → `BlockedCategoriesView`（分类列表 + 显示/隐藏切换） |
| 关于 | 应用版本号 |

### `NetworkTestView.swift`
网络调试页。提供测试按钮验证签名、登录、分类、漫画接口是否正常。

---

## Views/Helpers/（7 文件）

### `ThemeManager.swift`
主题管理器（单例 `@Observable`）。

| 成员 | 说明 |
|------|------|
| `var themeMode: ThemeMode` | 当前主题（system/light/dark），自动持久化 |
| `var colorScheme: ColorScheme?` | 返回对应 ColorScheme，system 返回 nil |
| `Color.accentPink` | 主题色 #ed6ea0 |
| `Color.mainBg(for:)` | 主背景色（暗 #1a1a2e / 亮 #f5f5f5） |
| `Color.cardBg(for:)` | 卡片背景色（暗 #2a2a3e / 亮 white） |
| `Color.secondaryText(for:)` | 次要文字色 |

### `CachedAsyncImage.swift`
带 NSCache 缓存的异步图片组件。

| 成员 | 说明 |
|------|------|
| `ImageCache.shared` | 全局缓存（200 张 / 100MB 上限） |
| `CachedAsyncImage<Placeholder>` | 优先读缓存，无缓存则异步下载并缓存 |

### `MediaImageView.swift`
Media → 图片视图的简单包装。自动处理 URL 拼接 + 圆角 + 占位符。

### `CommentCardView.swift`
评论卡片组件 + 用户信息弹窗。

| 成员 | 说明 |
|------|------|
| `comment: Comment` | 评论数据 |
| `showReplyCount: Bool` | 是否显示回复数（子评论页隐藏） |
| `onLike / onTap / onAvatarTap` | 点赞/点击评论/点击头像回调 |
| 视图 | 置顶标签 + 头像按钮/用户名/等级/时间 + 内容 + 点赞/回复按钮 |
| `formatTime(_:)` | ISO8601 → 相对时间 |
| `UserProfileOverlay` | ViewModifier：半透明背景 + 缩放动画弹出用户卡片（头像/昵称/头衔/等级/经验/签名） |
| `.userProfileOverlay(user:)` | View 扩展，绑定 `Creator?` 显示/隐藏用户弹窗 |

### `PaginationBar.swift`
翻页组件。

| 类型 | 说明 |
|------|------|
| `PaginationButtons` | 上一页/下一页圆形按钮 + 中间页码 |
| `PageJumpToolbarItem` | 工具栏页码按钮 + 跳页弹窗 + 恢复上次浏览页 |

### `BlockedCategoriesManager.swift`
屏蔽分类管理器（单例 `@Observable`）。

| 方法 | 说明 |
|------|------|
| `isBlocked(_:)` | 检查分类是否被屏蔽 |
| `toggle(_:)` | 切换屏蔽状态 |
| `filterComics(_:)` | 过滤掉包含屏蔽分类的漫画 |

### `ReadingProgressManager.swift`
阅读进度管理器（单例 `@Observable`）。

| 方法 | 说明 |
|------|------|
| `save(comicId:progress:)` | 保存进度（章节 order/title + 页码）到 UserDefaults |
| `get(comicId:) -> Progress?` | 读取进度 |
| `remove(comicId:)` | 删除进度 |

### `ReadingHistoryManager.swift`
阅读历史管理器（单例 `@Observable`）。

| 类型 / 方法 | 说明 |
|------------|------|
| `HistoryItem` | 历史记录条目：comicId, title, thumbPath, thumbServer, author, lastReadDate（Codable + Identifiable） |
| `var items: [HistoryItem]` | 历史记录列表（按时间倒序） |
| `record(comicId:title:thumbPath:thumbServer:author:)` | 记录阅读历史（去重 + 插入首位 + 上限 200 条） |
| `remove(comicId:)` | 删除指定漫画的记录 |
| `clearAll()` | 清空所有记录 |

---

## 关键架构模式

| 模式 | 说明 |
|------|------|
| `nonisolated` 前缀 | 所有 Model/Network 类型必须加，避免 `@MainActor` 默认隔离导致 Decodable 冲突 |
| `@Observable` | 所有 ViewModel + Manager 使用，SwiftUI 自动追踪属性变化 |
| 泛型 `APIEndpoint<Response>` | 通过 `where Response ==` 扩展实现类型安全的端点定义 |
| HMAC-SHA256 签名 | 每个请求 13 个必需头 + 签名 |
| `NSCache` 图片缓存 | `CachedAsyncImage` 全局缓存，200 张 / 100MB |
| Token 持久化 | `TokenStore` 使用 UserDefaults 存储 token，重启不丢失登录状态 |
| 快速启动 | 有 token 立即进入主页，后台异步验证 |
| `UserDefaults` 持久化 | 主题、阅读模式、屏蔽分类、阅读进度、阅读历史、翻页记忆、登录 token |
| 目标式 NavigationLink | ComicDetailView 内部导航使用 `NavigationLink { } label: { }`，避免嵌套 NavigationStack 中 value-based 导航解析失败 |
| `simultaneousGesture` | 阅读器中缩放/点击手势与 ScrollView 手势共存 |
| 容错解码 | Comment、CommentsData、RecommendedData 使用自定义解码器，单条数据解码失败不影响整体 |
| `ScrollViewReader` + `scrollTo` | 阅读器恢复位置使用程序化滚动，不依赖 binding 双向同步 |
| `.onScrollGeometryChange` | 阅读器通过 contentOffset 精确计算当前页码 |

---

## 构建命令

```bash
xcodebuild -project bika.xcodeproj -scheme bika \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
