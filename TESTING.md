# Bika-iOS 测试说明

## 目标
- 本仓库测试体系默认走纯 Mock，不访问真实后端、不依赖真实账号。
- 本地与 CI 统一使用 `bika.xctestplan`、`scripts/test.sh` 和共享 scheme。
- 当前已覆盖两类自动化测试：
  - `Unit`：`bikaTests`
  - `UI Smoke`：`bikaUITests`

## 环境要求
- Xcode：`26.4`
- Command Line Tools：与 Xcode 版本保持一致
- 模拟器：默认 `iPhone 17`
- 推荐系统：与 Xcode 26.4 兼容的 macOS

## 本地目录约定
- 工程：`/Users/zyq/Desktop/xcode/Bika-iOS/bika.xcodeproj`
- 测试计划：`/Users/zyq/Desktop/xcode/Bika-iOS/bika.xctestplan`
- 脚本：`/Users/zyq/Desktop/xcode/Bika-iOS/scripts/test.sh`
- 结果目录：`/Users/zyq/Desktop/xcode/Bika-iOS/artifacts/test-results`
- DerivedData：`/tmp/bika-derived`

## 本地执行
- 先给脚本执行权限：
  - `chmod +x /Users/zyq/Desktop/xcode/Bika-iOS/scripts/test.sh`
- 运行单元测试：
  - `./scripts/test.sh unit`
- 运行 UI Smoke：
  - `./scripts/test.sh ui-smoke`
- 一次性跑全量：
  - `./scripts/test.sh all`
- 只做编译测试产物：
  - `./scripts/test.sh build-for-testing`
- 清理本地产物：
  - `./scripts/test.sh clean`

## 可选环境变量
- `SIMULATOR_NAME`
  - 默认值：`iPhone 17`
  - 如果另一台 Mac 没装该模拟器，可在命令前覆盖，例如：
  - `SIMULATOR_NAME="iPhone 17 Pro" ./scripts/test.sh unit`
- `DERIVED_DATA_PATH`
  - 默认值：`/tmp/bika-derived`
- `RESULTS_DIR`
  - 默认值：`./artifacts/test-results`
- `BUILD_CONFIGURATION`
  - 默认值：`Debug`

## 测试计划说明
- `bika.xctestplan` 固定两套配置：
  - `Unit`
  - `UI Smoke`
- 脚本执行时会显式指定：
  - `-only-test-configuration`
  - `-only-testing:bikaTests` 或 `-only-testing:bikaUITests`
- 这样可以保证同一份 test plan 同时服务本地和 GitHub Actions。

## Mock 策略
- App 在 UI 测试模式下会读取 `launchArguments` / `launchEnvironment`。
- `AppDependencies` 会切换到：
  - `MockURLProtocol`
  - 本地 fixture 路由
  - 测试专用 `UserDefaults` suite
  - 测试图片数据加载器
- UI Smoke 默认走 mocked 已登录态，不需要真实账户。

## 覆盖范围
- `APIClient`
  - 成功解码
  - 业务错误抛出
  - 401 / 无 token / 解码错误
  - `image-quality` 请求头
- `SearchViewModel`
  - 关键词 trim
  - `activeKeyword` 锁定
  - 搜索页码持久化
- `CommentsViewModel` / `ChildCommentsViewModel`
  - 只在最后一项翻页
  - 防止重复触发
  - 空页 / 重复页 / 页码不前进时停住
- `ReaderViewModel`
  - 切章取消旧任务
  - 过期响应不覆盖
  - 阅读模式持久化
- `ComicDetailViewModel`
  - 章节分页异常收口
  - 最终按章节顺序排序
- `ReadingProgressManager`
  - 保存 / 读取 / 删除
- `UI Smoke`
  - 搜索、分页、排序、返回恢复
  - 评论 / 子评论页面不死循环
  - 阅读器进度恢复
  - 图片质量设置持久化并回传到 mock 请求

## GitHub Actions
- CI 配置文件：`/Users/zyq/Desktop/xcode/Bika-iOS/.github/workflows/ios-tests.yml`
- 触发条件：
  - `push`
  - `pull_request`
- Job：
  - `unit`
  - `ui-smoke`
- 两个 job 都会上传 `xcresult` 方便排查失败。

## 两台 Mac 保持一致的建议
- 保持同一大版本 Xcode，优先统一到 `26.4`
- 统一模拟器名称为 `iPhone 17`
- 不要把真实账号和真实后端接回自动化
- 回归入口只使用：
  - `./scripts/test.sh unit`
  - `./scripts/test.sh ui-smoke`
  - `./scripts/test.sh all`
