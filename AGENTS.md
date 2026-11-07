# AGENTS.md

本文件约束在本仓库工作的编码代理。项目目标与交付要求来自项目书
（不随仓库分发；以仓库内 README、AGENTS 与 TEST_REPORT 为准）。

## 项目一句话

本地 SwiftUI App：读取 PhotoKit 中 iPhone 16/17 的 HEIC **原始资源文件**，只追加
纹理与颗粒（Texture / Grain），另存为相册新照片。原图不覆盖、不转码、不上传。当前版本 1.5.0（build 6），
包含品牌「纹粒 / Texel」、四语言本地化、5 张 / 日免费额度、StoreKit 2 一次性 Pro 内购、
首页设置入口与应用内语言切换、首次额度用尽的一次性 Pro 介绍，以及 1.5 的 iOS 分组表面 / 狐橙视觉重构。

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
```

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
   注入测试或显式 App Group 环境。模拟器无 target entitlement 时退回进程默认 Keychain 组，
   这只能证明 App 内持久化，不能写成 App / 扩展跨进程已验证。
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

## 代码约定

- Swift 5 模式，iOS 18+；App 为 SwiftUI，分享扩展用 `UIHostingController` 承载 SwiftUI。
- 注释与 commit message 用英文；用户可见文案全部走 `Resources/Localization/*.xcstrings`，源语言
  `zh-Hans`，当前支持 zh-Hans / zh-Hant / en / ja。不要在 Swift 里写只适配一种语言的拼接文案。
  内部 Bundle ID、Keychain 服务名、StoreKit Product ID 与仓库名保留 LingXiStyle，避免升级断档。
- 新增公开 API 要显式 `public`，并保持值类型 `Sendable`。
- 临时文件只写 `FileManager.default.temporaryDirectory`，任务结束删除；探针脚本放 `/tmp` 或 `.tmp/`，
  不提交。
- 不引入第三方 UI 框架、不新增网络依赖。

## 测试与交付

- 修改 Kit / Engine 必须跑对应 macOS 测试 scheme；修改 App 必须至少做一次
  `generic/platform=iOS` Debug 与 Release 构建。修改任务生命周期必须跑 `ConversionRunTests`。
- 真机验证状态以 `TEST_REPORT.md` 为准，不得把「编译通过」写成「真机通过」。
- 1.5 已完成 Debug / Release、签名 Debug 构建与自动化测试（Kit 27 / Purchase 21 / Engine 2 / Core 14 执行、2 跳过）；在 iPhone 17（402×874 pt）复验 zh-Hans / en 首页、选择、处理中、结果、设置、Pro、额度耗尽、深色与 accessibility-extra-large，并在 iPhone Duo（466×678 pt）复验 5/5 紧凑首页。权限拒绝页、分享扩展、快捷指令、真实交易与真机矩阵仍未逐项验证；不得把模拟器通过写成真机通过。
- 已有 48MP 实拍 HEIC 的引擎层与 1.2 App 端到端验证，记录见 `TEST_REPORT.md`；1.5 引擎算法未改，仅更新错误文案。真实 App Store 交易 / 退款、分享扩展、快捷指令与真机系统权限矩阵仍需确认。
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
| `Kit/Sources/LingXiKit` | HEIF 解析、兼容性、无损校验、ConversionRun、诊断格式化 |
| `Core/Sources/StylePortCore` | vendor 风格核心，尽量不改 |
| `ShareExtension/Sources` | 分享扩展入口与 SwiftUI 流程 |
| `Resources/Localization` | String Catalog（App / 分享扩展 / 快捷指令 / Info.plist） |
