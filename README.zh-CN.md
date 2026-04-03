[English](README.md)

# Bika-iOS

一个基于 SwiftUI 的 iOS 漫画阅读项目，把浏览、搜索、详情、阅读、评论、收藏和进度恢复串成一条完整的使用链路。

> 状态：可持续维护  
> 平台：iOS 18.0+  
> 技术栈：SwiftUI、`@Observable`、async/await、Xcode Test Plan

## 项目简介

Bika-iOS 不是只展示几个独立页面的 Demo，而是围绕真实阅读流程搭建的完整客户端。项目覆盖了从发现内容到长时间阅读的核心体验：

- 通过分类和排行榜浏览漫画
- 通过搜索完成排序、翻页与结果恢复
- 查看漫画详情、章节、标签、作者和推荐内容
- 从上次阅读到的章节与页码继续阅读
- 浏览评论与子评论
- 管理收藏、历史记录、主题模式和图片质量偏好

除了作为一个可运行的应用工程，这个仓库也适合作为 SwiftUI 项目实践参考：

- 基于 `@Observable` 的状态管理
- 使用 async/await 的网络请求与页面状态切换
- 可复用的分页结果页模式
- 基于 mock 的单元测试和 UI Smoke 测试

## 功能特性

- 分类浏览与分页漫画列表
- 支持多个时间范围的排行榜页面
- 支持排序、翻页和结果恢复的搜索结果页
- 包含元数据、章节入口、推荐内容和评论入口的详情页
- 支持横向翻页与纵向滚动两种模式的阅读器
- 阅读进度持久化与继续阅读恢复
- 评论和子评论浏览、点赞、回复
- 收藏、历史记录、主题模式、图片质量和内容过滤设置

## 架构亮点

### 统一的分页漫画结果模式

多个列表型页面复用了同一套分页逻辑，而不是每个页面各自维护一份独立状态机。

- [ComicResultsViewModel.swift](bika/ViewModels/ComicResultsViewModel.swift)
- [PaginatedComicResultsView.swift](bika/Views/Helpers/PaginatedComicResultsView.swift)

### 组合式详情页结构

漫画详情页已经拆成更清晰的分区组合，而不是继续堆在一个超长的 View 文件里。

- [ComicDetailView.swift](bika/Views/ComicDetailView.swift)
- [ComicDetailSections.swift](bika/Views/ComicDetailSections.swift)

### 阅读恢复与连续性

阅读器会持久化章节和页码位置，用户可以更自然地回到上次中断的位置。

- [ComicReaderView.swift](bika/Views/ComicReaderView.swift)
- [ReadingProgressManager.swift](bika/Views/Helpers/ReadingProgressManager.swift)

### 可注入依赖与 mock 优先测试

应用支持切换到基于 fixture 的依赖配置，方便本地和 CI 做稳定、可重复的验证。

- [AppDependencies.swift](bika/Support/AppDependencies.swift)
- [MockURLProtocol.swift](bika/Support/MockURLProtocol.swift)
- [SmokeFixtureRouter.swift](bika/Support/SmokeFixtureRouter.swift)

## 项目结构

```text
.
├── bika/                  # 应用源代码
├── bikaTests/             # 单元测试
├── bikaUITests/           # UI Smoke 测试
├── scripts/test.sh        # 统一的本地测试入口
├── TESTING.md             # 测试说明
├── bika项目文档.md         # 架构与维护说明
└── .github/workflows/     # CI 工作流
```

`bika/` 目录内部按职责划分：

- `Models`：响应模型与解码规则
- `Network`：接口定义、API Client、签名与错误类型
- `Support`：依赖注入、Mock、导航恢复、存储与辅助能力
- `ViewModels`：页面状态、分页流程与异步业务逻辑
- `Views`：页面与功能组合
- `Views/Helpers`：共享 UI、阅读器辅助、分页与图片相关能力

## 快速开始

### 环境要求

- Xcode `26.4`
- iOS Simulator
- 默认模拟器目标：`iPhone 17`

### 常用命令

```bash
chmod +x ./scripts/test.sh
./scripts/test.sh build-for-testing
./scripts/test.sh unit
./scripts/test.sh ui-smoke
./scripts/test.sh all
```

## 测试

当前仓库包含两层自动化测试：

- `Unit`
- `UI Smoke`

测试默认基于 mock 运行，不依赖真实后端和真实账号。

更多说明见：

- [TESTING.md](TESTING.md)

## CI

GitHub Actions 工作流：

- [.github/workflows/ios-tests.yml](.github/workflows/ios-tests.yml)

当前会在 `push` 和 `pull_request` 上执行：

- `unit`
- `ui-smoke`

## 后续维护方向

当前建议的维护方向：

- 继续把更多列表型页面迁到统一的分页结果模式
- 继续减少在 View 中直接扩散共享单例
- 持续补强 ViewModel 与 Support 层的单元测试
- 让关键失败路径保持可见，而不是静默降级

## 文档

- 测试说明：[TESTING.md](TESTING.md)
- 架构与维护说明：[bika项目文档.md](bika项目文档.md)

## License

当前仓库尚未包含许可证文件。
