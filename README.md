# Bika-iOS

一个基于 SwiftUI 构建的 iOS 漫画阅读应用工程，当前重点放在可维护性、测试稳定性和渐进式重构，而不是一次性推翻重写。

## 项目状态

当前项目已经完成一轮面向维护性的收口，重点解决了这些问题：

- 依赖注入边界不清
- 分页列表逻辑重复
- 评论解码过于宽松
- 用户动作失败时提示不明确
- 详情页和阅读器职责过重

截至 `2026-04-03`，本地验证结果：

- `build-for-testing` 通过
- `unit` 通过
- `ui-smoke` 通过

## 技术栈

- Swift 5
- SwiftUI
- `@Observable`
- async/await
- Xcode Test Plan
- `xcodebuild` + shell script 测试入口

## 主要能力

- 分类浏览
- 漫画搜索
- 排行榜
- 漫画详情
- 评论与子评论
- 阅读器进度恢复
- 收藏与阅读记录
- 主题与图片质量设置

## 当前架构方向

项目当前不是“完全重做架构”，而是在现有 SwiftUI 方向上做渐进式治理。

核心原则：

- View 负责布局与轻量编排
- ViewModel 负责状态和异步动作
- 共享对象作为默认注入源，而不是页面里的直接业务入口
- 分页漫画列表优先复用统一模式
- 模型解码遵循“关键字段严格、非关键字段宽容”

关键实现位置：

- 统一分页列表：
  - [ComicResultsViewModel.swift](bika/ViewModels/ComicResultsViewModel.swift)
  - [PaginatedComicResultsView.swift](bika/Views/Helpers/PaginatedComicResultsView.swift)
- 详情页拆分：
  - [ComicDetailView.swift](bika/Views/ComicDetailView.swift)
  - [ComicDetailSections.swift](bika/Views/ComicDetailSections.swift)
- 依赖装配：
  - [AppDependencies.swift](bika/Support/AppDependencies.swift)
- 测试 mock 基础设施：
  - [MockURLProtocol.swift](bika/Support/MockURLProtocol.swift)
  - [SmokeFixtureRouter.swift](bika/Support/SmokeFixtureRouter.swift)

## 目录结构

```text
.
├── bika/                  # App 源码
├── bikaTests/             # Unit tests
├── bikaUITests/           # UI smoke tests
├── scripts/test.sh        # 统一测试入口
├── TESTING.md             # 测试说明
├── bika项目文档.md         # 架构与维护文档
└── .github/workflows/     # CI
```

## 本地运行与测试

环境要求：

- Xcode `26.4`
- 模拟器默认 `iPhone 17`

常用命令：

```bash
chmod +x ./scripts/test.sh
./scripts/test.sh unit
./scripts/test.sh ui-smoke
./scripts/test.sh all
```

更多测试说明见 [TESTING.md](TESTING.md)。

## CI

GitHub Actions 配置位于：

- [.github/workflows/ios-tests.yml](.github/workflows/ios-tests.yml)

当前包含两个 job：

- `unit`
- `ui-smoke`

## 维护建议

如果你要继续在这个仓库上开发，最值得坚持的约束是：

- 新增分页列表页时优先复用统一分页模式
- 新增网络请求通过可注入 client 进入
- 不要在 View 里直接扩散 `APIClient.shared` 或 `UserDefaults.standard`
- 用户动作失败要给可见反馈
- 新增模型解码时明确关键字段与降级字段

## 文档

- 项目架构与维护约定：[bika项目文档.md](bika项目文档.md)
- 测试说明：[TESTING.md](TESTING.md)
