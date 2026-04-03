# Bika-iOS 测试说明

## 目标

- 默认使用 Mock 与本地 fixture，不访问真实后端、不依赖真实账号。
- 本地与 CI 共用同一套 `xctestplan`、`scheme` 与脚本入口。
- 回归目标不是只看“能不能编译”，而是同时覆盖核心逻辑和主交互链路。

## 测试分层

### 1. Unit

- 目标：验证 ViewModel、Support、Network 等核心逻辑。
- 对应 target：`bikaTests`
- 对应 test plan 配置：`Unit`
- 当前重点覆盖：
  - `APIClient` 业务错误、401、无 token、解码错误、请求头
  - `AuthViewModel` 登录、登出、token 校验回退
  - `SearchViewModel` 搜索关键词 trim、分页持久化
  - `ComicResultsViewModel` 统一分页列表的翻页、排序、恢复
  - `CommentsViewModel` / `ChildCommentsViewModel` 的分页边界与失败路径
  - `CommentModels` 的关键字段严格解码、非关键字段宽容降级
  - `ReaderViewModel` 的章节切换、旧任务失效、模式持久化
  - `ReadingProgressManager` 的保存、读取、删除
  - `SettingsViewModel` 的持久化与诊断信息
  - `Media.imageURL` 的路径规范化

### 2. UI Smoke

- 目标：验证主用户路径没有因为重构而回归。
- 对应 target：`bikaUITests`
- 对应 test plan 配置：`UI Smoke`
- 当前重点覆盖：
  - 搜索、翻页、排序、详情返回
  - 评论页与子评论页可打开且不会死循环
  - 阅读器进度保存与重启恢复
  - 设置页图片质量持久化与 mock 请求回传

## 环境要求

- Xcode：`26.4`
- Command Line Tools：与 Xcode 版本保持一致
- 模拟器：默认 `iPhone 17`
- iOS Runtime：可运行 `iPhone 17` 的最新 Simulator Runtime

## 目录约定

- 工程：`./bika.xcodeproj`
- 测试计划：`./bika.xctestplan`
- 脚本：`./scripts/test.sh`
- 结果目录：`./artifacts/test-results`
- DerivedData：`/tmp/bika-derived`

## 本地执行

首次使用可先给脚本执行权限：

```bash
chmod +x ./scripts/test.sh
```

常用命令：

```bash
./scripts/test.sh unit
./scripts/test.sh ui-smoke
./scripts/test.sh all
./scripts/test.sh build-for-testing
./scripts/test.sh clean
```

## 可选环境变量

```bash
SIMULATOR_NAME="iPhone 17"
DERIVED_DATA_PATH="/tmp/bika-derived"
RESULTS_DIR="./artifacts/test-results"
BUILD_CONFIGURATION="Debug"
```

常见覆写示例：

```bash
SIMULATOR_NAME="iPhone 17 Pro" ./scripts/test.sh unit
```

## 脚本行为

测试脚本见 [scripts/test.sh](scripts/test.sh)。

它做了这些事情：

- 显式检查目标模拟器是否存在
- 统一使用 `bika.xctestplan`
- `unit` 与 `ui-smoke` 默认都会先执行 `build-for-testing`
- `ui-smoke` 会在执行前主动准备模拟器状态
- 输出 `xcresult` 到 `artifacts/test-results`

## Mock 策略

测试模式由 `AppDependencies` 接管，切换到测试依赖：

- `MockURLProtocol`
- `SmokeFixtureRouter`
- 测试专用 `UserDefaults` suite
- `FixtureImageDataLoader`
- Mock 已登录态和可重置的持久化状态

这意味着：

- Unit 不依赖外网
- UI Smoke 不依赖真实账号
- 两台机器跑同一套脚本时结果更稳定

## 结果产物

- Unit：`artifacts/test-results/unit.xcresult`
- UI Smoke：`artifacts/test-results/ui-smoke.xcresult`

最新一轮本地验证时间：

- `2026-04-03`
- `./scripts/test.sh unit` 通过
- `./scripts/test.sh ui-smoke` 通过

## CI

CI 配置位于 [ios-tests.yml](.github/workflows/ios-tests.yml)。

当前包含两个 job：

- `unit`
- `ui-smoke`

两者都会上传 `xcresult`，便于失败后定位。

## 日常维护建议

- 提交 PR 前至少跑 `./scripts/test.sh unit`
- 改动分页列表、详情、评论、阅读器或设置时，建议跑 `./scripts/test.sh all`
- 新增分页列表页时，优先复用统一分页模式，再补共享行为测试
- 新增模型解码时，明确“关键字段”和“降级字段”的边界，并补单测
