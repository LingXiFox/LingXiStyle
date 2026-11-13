# AGENTS.md

本文件约束在本仓库工作的编码代理。项目目标与交付要求来自项目书
（不随仓库分发；以仓库内 README、AGENTS 与 TEST_REPORT 为准）。

## 项目一句话

本地 SwiftUI App：读取 PhotoKit 中 iPhone 16/17 的 HEIC **原始资源文件**，只追加
纹理与颗粒（Texture / Grain），另存为相册新照片。原图不覆盖、不转码、不上传。当前版本 1.9.1（build 11），
包含品牌「纹粒 / Texel」、四语言本地化、5 张 / 日免费额度、StoreKit 2 多档 Pro 内购、
首页设置入口与应用内语言切换、首次额度用尽的一次性 Pro 介绍，以及 1.5 的 iOS 分组表面 / 狐橙视觉重构。
1.9.1 新增成果保险箱（默认保留 7 天，重存不扣额度）、任务历史与中断恢复、日卡 / 周订阅 / 月订阅 / 永久四档 Pro、
每设备一次的 24 小时免费体验，以及 iPad 原生两栏与 macOS 原生 App（TexelMac）。
1.8.1 新增实况照片双模式（仅主帧 / 完整处理，均只计 1 张额度）、9 步首启教程与常驻入口、
iPhone Duo 外屏全流程与内屏双栏；iPhone / iPad 共用 App，Mac 为独立 target。
1.7.1 是发布验证补强：新增真实 HEIC 端到端集成测试（真实 ConversionService、PhotoKit 保存回读、
Keychain 额度扣减与持久化）、分享扩展 12 条异常 / 取消 / 超时 / 重试状态机测试、快捷指令 9 条批量与额度测试，
以及 1 条 XCUITest 启动 / 首页 / 设置 / Pro 入口冒烟；CI 增加集成测试与启动冒烟，并预授权模拟器相册权限。
1.7.0 保留 CI 双 SDK 矩阵、分享扩展阻塞修复、共享 Keychain 组和免费 Offer Code 测试。

## 构建与验证

```bash
xcodegen generate
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates build

xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiPurchaseTests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiIntegrationTests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiUITests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiMacPipelineTests \
  -destination 'platform=macOS,arch=arm64' test

xcodebuild -project LingXiStyle.xcodeproj -scheme TexelMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

集成测试运行前必须给宿主授权：
`xcrun simctl privacy booted grant photos com.lingxifox.Texel.IntegrationHost`
和 `xcrun simctl privacy booted grant photos-add com.lingxifox.Texel.IntegrationHost`。

改了 `project.yml` 或新增文件后必须重新 `xcodegen generate`，否则 target 源列表不会更新
（历史坑：测试 target 空源，报 `Cannot find executable for CFBundle ... xctest`）。

## 不可破坏的约束

1. **唯一入口**：App、快捷指令、分享扩展都只能调用
   `Services/Sources/LingXiServices/ConversionService.swift` 的 `ConversionService.shared.convert`。
   不要在各入口各写一份编码管线。
2. **不重编码**：转换路径禁止经过 `UIImage` / `CGImageDestination` / `sips`。
   `UIImage` 只用于缩略图与预览。
3. **不覆盖原图**：只用 `PHAssetCreationRequest.addResource(with: .photo, fileURL:)` 新建 Asset，
   保存后必须回读确认仍是 HEIC。
4. **不造假进度**：阶段只能由引擎真实回调驱动；没有百分比，不用定时器推进业务状态。
5. **兼容性先判后转**：非 HEIF、Live Photo、RAW、已带纹理与颗粒必须在
   `CompatibilityEvaluator` 里明确处理，用户可见错误走 String Catalog，原始码只放诊断。
6. **设计令牌**：颜色、间距、圆角、字体全部走 `App/Sources/DesignSystem/Tokens.swift`；
   动效走 `Motion.swift`，循环动画必须尊重 Reduce Motion。
7. **同一个服务二进制**：`PhotoLibraryService` 与 `ConversionService` 属于 `LingXiServices`
   framework，App 与 ShareExtension 都链接它，不要复制源文件到两个 target。
8. **任务会话隔离**：转换队列由 `Kit/Sources/LingXiKit/ConversionRun.swift` 的 session token 驱动。
   所有 stage / result / finish 回调必须先校验所属会话；`saved` 永不重转，`failed` 才可重试；
   `reset()` 只能 retire 工作目录，等活跃操作结束后再删除，不能抽走任务正在读的文件。
9. **不重复保存**：保存已写入相册但回读 HEIC 失败时，记录 `SavedPhoto.warning`，不要抛错把该项
   标成失败；否则重试会再次写入相册。
10. **真实进度**：`ConversionService` 在保存前发 `.saving`、成功后发 `.finished`；iCloud 下载
   进度只能来自 `PHAssetResourceRequestOptions.progressHandler`。禁止定时器、假百分比和
   用动画推进业务状态。
11. **按需权限**：启动时不要请求相册权限；图库选择后再请求 read，保存前才请求 addOnly；
   文件导入不需要相册权限。权限被拒后要提供系统设置与文件导入两条恢复路径。
12. **公开 API**：禁止 `photos-redirect://` 等未公开 scheme。结果页用应用内预览、`ShareLink`
   与已保存 Asset 标识完成查看 / 分享，不依赖跳转系统「照片」。
13. **图片加载**：`PHImageManager` 只接受非 degraded 的最终图，并处理 error / cancelled；
   缩略图请求要支持任务取消，避免长期停留在低清预览。
14. **额度唯一入口**：免费额度只能在 `ConversionService` 里检查 / 预留 / 提交 / 释放；
   App、分享扩展、快捷指令都不得自行计数或绕过。默认每天 5 张，失败、跳过、不兼容、
   取消、保存失败不扣；只有成功保存或成功导出后才提交。批量超出时只处理剩余额度。
15. **额度存储**：生产默认 `KeychainQuotaStore` 的槽位账本（`SecItemAdd` 原子占位），
   跨进程共享靠 Keychain Access Group；不要改回普通 UserDefaults 读改写。SQLite 只用于
   注入测试或显式 App Group 环境。Xcode 自动签名构建的模拟器产物会生成带共享组的
   `Simulated.xcent`，可用于验证 App / 扩展同账本；但真机 distribution 签名仍需单独复验，
   不得把手动 `codesign --deep` 重签后的结果当成有效证据。
16. **内购只认 StoreKit 2 验证**：`isPro` 必须来自已验证的 `Transaction` 与
   `Transaction.currentEntitlements`；不得用本地 bool、按钮回调、UserDefaults 或
   `SKTestSession` 结果直接解锁。退款 / 撤销后必须回到免费额度。
17. **价格只读 `Product.displayPrice`**：UI、测试、文档不得硬编码 USD / CNY / JPY / EUR。
   商品加载失败显示本地化错误与重试，不得显示虚构价格。
18. **StoreKit 测试配置只在 Debug**：`Configuration.storekit` 绑定到 Debug scheme；
   Release / 真机生产不得启用本地测试商品或开发购买旁路。
19. **1.5 视觉**：结构色用 iOS 语义色，交互强调色只用狐橙 `#E8A13A`；每屏最多一个
   强调填充。`surfaceElevated` 是浅色白 / 深色 `#2C2C2E`，保证卡片在两种外观下可见；
   不恢复 `accentSecondary`、渐变边框、`ConversionStageAura`、扫光或呼吸光。
20. **跨入口额度竞态**：预检后额度被另一入口抢走时，当前项与剩余 pending 项必须转
   `deferred`，不得记成失败，也不得把已保存项重转；若一张都没保存，回到选择页。
21. **分享扩展类型**：向 `NSItemProvider` 要具体注册类型，优先 `public.heic` / `public.heif`，
   再取任一具体图片类型，最后才回退 `public.fileURL`；不要向抽象 `public.image` 直接要文件。
   读取必须有 3 秒数据回退与 15 秒超时；`process` 不能再把当前 `reading` 阶段当成忙碌而
   静默丢弃已复制的文件。
22. **Keychain fail-closed**：配置了共享组但进程没有对应 entitlement 时，必须抛
   `QuotaError.database`，不得静默改用另一套 Keychain 条目或本地 bool。
23. **隐私清单**：App 与 Share Extension 各自维护 `PrivacyInfo.xcprivacy`。App 使用
   `UserDefaults` / `CA92.1`；扩展使用 `FileTimestamp` / `C617.1` 清理自身临时目录。
   新增 required reason API 或第三方 SDK 时必须同步更新对应清单，不得只依赖 App 清单。
24. **通用购买**：iOS / iPadOS 与 `TexelMac` 必须使用同一 Bundle ID `com.lingxifox.Texel`，分享扩展用
   `com.lingxifox.Texel.Share`；不得恢复 `com.lingxifox.Texel.Mac` 或为 macOS 新建一套商品。四个商品 ID 共用，
   Mac Keychain 共享组与 iOS 相同；App Store Connect 添加 macOS 平台是人工步骤，见
   `docs/app-store/universal-purchase.md`。

## 代码约定

- Swift 5 模式，iOS 18+；App 为 SwiftUI，分享扩展用 `UIHostingController` 承载 SwiftUI。
- 注释与 commit message 用英文；用户可见文案全部走 `Resources/Localization/*.xcstrings`，源语言
  `zh-Hans`，当前支持 zh-Hans / zh-Hant / en / ja。不要在 Swift 里写只适配一种语言的拼接文案。
  Bundle ID：主 App 与 `TexelMac` 同为 `com.lingxifox.Texel`，分享扩展为 `com.lingxifox.Texel.Share`；
  共享 Keychain 组使用 `$(AppIdentifierPrefix)com.lingxifox.Texel.shared`；Keychain 服务名、StoreKit Product ID
  与仓库名保留 LingXiStyle。
- 新增公开 API 要显式 `public`，并保持值类型 `Sendable`。
- 临时文件只写 `FileManager.default.temporaryDirectory`，任务结束删除；探针脚本放 `/tmp` 或 `.tmp/`，
  不提交。
- 不引入第三方 UI 框架、不新增网络依赖。

## 测试与交付

- 修改 Kit / Engine 必须跑对应 macOS 测试 scheme；修改 App 必须至少做一次
  `generic/platform=iOS` Debug 与 Release 构建。修改任务生命周期必须跑 `ConversionRunTests`。
- 真机验证状态以 `TEST_REPORT.md` 为准，不得把「编译通过」写成「真机通过」。
- 交付默认：本地 commit 完成后直接 `git push origin main`，不要只留本地提交；推送前仍需确认工作区干净、无凭据与签名资产。
  1.7.1 的 GitHub Actions [run 42435430433](https://github.com/LingXiFox/LingXiStyle/actions/runs/42435430433)（commit `365abf5`）四个 job 全绿；iOS 18.5 购买 23、集成 29（0 跳过）、UI 1，iOS 26 购买 24（1 跳过）、集成 29（0 跳过）、UI 1。此前跳过的两条 PhotoKit 保存测试已通过 TCC auth_version 修复实际执行。
- 1.9.1 本机七套测试 168 项 / 3 跳过 / 0 失败：Kit 73、Purchase 29、Engine 5、Core 15（2 跳过）、
  Integration 37、UI 6（1 跳过）、MacPipeline 3；iOS Debug / Release 与 TexelMac Debug / Release 构建通过。
  通用购买的线上 App Store Connect 配置仍未完成，见 `docs/app-store/universal-purchase.md`。
- 已有 48MP 实拍 HEIC 的引擎层与 1.2 App 端到端验证，记录见 `TEST_REPORT.md`；1.7 引擎算法未改。真实 App Store 交易 / 退款、真机 Keychain 共享组与系统权限矩阵仍需确认。
- 语言偏好只写 `LingXiStyle.appLanguage`，非「跟随系统」时再写 `AppleLanguages`；不要让 SwiftUI 预览或测试进程持久化语言设置。
- 修改 HEIF 解析后必须跑 `LingXiKitTests` 的 `iref` 回归用例；修改额度必须同时跑
  `QuotaTests` 与 `KeychainQuotaTests`；修改购买必须跑 `LingXiPurchaseTests`。

## 目录速查

| 路径 | 内容 |
| --- | --- |
| `App/Sources/Views` | 四态页面、权限页、Pro 购买页、额度耗尽页、设置页 |
| `App/Sources/Components` | PhotoHeroCard、缩略图条、徽章、进度、结果卡、诊断、额度徽章 |
| `App/Sources/DesignSystem` | 颜色 / 间距 / 字体 / 动效 |
| `App/Sources/AppModel.swift` | 任务会话、队列、选择、导入、取消、诊断、一次性额度提示 |
| `App/Sources/Models/AppLanguage.swift` | 应用语言偏好与 `AppleLanguages` 写入 |
| `App/Sources/Integrations/Shortcuts` | AppIntent 与 AppShortcutsProvider |
| `Services/Sources/LingXiServices` | PhotoKit 适配 + ConversionService |
| `Engine/Sources/LingXiEngine` | URL → URL 固定管线 |
| `Kit/Sources/LingXiKit` | HEIF 解析、兼容性、无损校验、ConversionRun、VaultStore、TaskJournal、Pro 权益 |
| `Mac/Sources` | macOS 原生界面与模型（TexelMac target） |
| `Core/Sources/StylePortCore` | vendor 风格核心，尽量不改 |
| `ShareExtension/Sources` | 分享扩展入口与 SwiftUI 流程 |
| `Resources/Localization` | String Catalog（App / 分享扩展 / 快捷指令 / Info.plist） |
| `App/Resources/PrivacyInfo.xcprivacy` | App 隐私清单：无跟踪 / 无数据收集，UserDefaults CA92.1 |
| `ShareExtension/Resources/PrivacyInfo.xcprivacy` | 扩展隐私清单：FileTimestamp C617.1（临时目录清理） |
| `.github/workflows` | CI：XcodeGen 一致性、四语言完整性、凭据扫描、StoreKit 配置、iOS 18.5 / 26.x / 27.2 三套构建与测试、macOS 单元测试与 TexelMac 构建 |
| `.github/actions/setup` | CI 复用的 Xcode 选择 + XcodeGen 安装 action |

## Resource Lifecycle and Cleanup

**All resources started or allocated by an Agent must be properly released when they are no longer needed.**

### Mandatory Rules

1. **Ownership**: Track processes, temporary files, simulators, servers, and other resources created during task execution.
2. **Cleanup on Exit**: Release owned resources when a task finishes, fails, or is interrupted.
3. **No Orphan Processes**: Do not leave unnecessary background processes running after completing a task.
4. **Scoped Cleanup**: Only terminate processes and remove resources owned by the current task. Never indiscriminately kill unrelated processes.
5. **Graceful Shutdown**: Prefer normal termination. Use forced termination only when graceful shutdown fails.
6. **Temporary Artifacts**: Remove task-specific temporary files, caches, and build artifacts when they are no longer required. Preserve reusable caches and user data.
7. **Verification**: Confirm that resource cleanup succeeded before reporting task completion.
8. **Failure Handling**: Cleanup must execute even when builds, tests, or other operations fail. Preserve the original failure status.

### Xcode and iOS Simulator

- Shut down simulators started by the current task after testing.
- Terminate task-owned `xcodebuild` and related processes when no longer needed.
- Prevent orphaned simulator processes from accumulating between test runs.
- Use `trap` or equivalent cleanup handlers in automation scripts.
- Avoid unnecessary concurrent simulator instances.
- Never erase simulator devices, installed runtimes, or persistent application data unless explicitly authorized.
- Do not force-terminate shared CoreSimulator services while other development sessions are active.

### Completion Criteria

A task is considered complete only when:

- Its intended operation has finished.
- Its temporary resources have been released.
- No unnecessary task-owned background processes remain.
- Any cleanup failure has been reported.

**Resource cleanup is part of task execution, not an optional post-processing step.**

## Long-running Tasks and CI

- Never poll long-running tasks through repeated LLM calls.
- After pushing code, identify the GitHub Actions run
  associated with the pushed commit.
- Monitor CI using `gh run watch <run-id> --exit-status
  --compact --interval 60` in a background bash task.
- End the agent turn when no other work remains.
- Resume automatically when the background task completes.
- On failure, retrieve failed logs using
  `gh run view <run-id> --log-failed`.
- Never use `sleep` followed by repeated model-driven
  status checks.
- Avoid duplicate CI watchers for the same run.
