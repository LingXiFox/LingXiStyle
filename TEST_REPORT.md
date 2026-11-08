# 测试报告（纹粒 / Texel 1.7.1）

- 日期：2026-11-07
- 版本：1.7.1（build 9）
- 结论：本机 Debug / Release generic iOS 构建通过，六套自动化测试合计执行 98 项、
  通过 96 项、跳过 2 项；新增的 29 项集成测试真实读取 48MP HEIC、调用
  `ConversionService`、写入 PhotoKit 并扣减 Keychain 额度，另有 1 项 XCUITest 覆盖
  安装、启动、首页、设置与 Pro 入口。iPhone 17（iOS 27.3）签名构建完成目视验证；
  Duo 验证首页、设置与 Pro 页，选片仍受模拟器远程输入限制。
  CI 的 iOS 18.5 与 26.x 集成测试均 29 项执行 / 0 跳过 / 0 失败；此前两条 PhotoKit 保存测试已实际执行。
  本机没有 iOS 18 / 26 运行时；真机、真实 App Store 交易与部分失败路径仍未验证。
  本报告只记录实际执行过的证据。

## 1. 环境

| 项 | 值 |
| --- | --- |
| 主机 | macOS 27.3（26C5035r），Apple Silicon |
| Xcode | 27.3（27C5020n），iPhoneOS 27.3 SDK |
| Swift | Swift 5 语言模式 |
| 部署目标 | iOS 18.0 |
| 工程生成 | XcodeGen 2.46.0 |
| 签名 | Xcode 自动签名；本地 Team 不写入仓库 |
| 模拟器 | iPhone 17，iOS 27.3，402 × 874 pt，UDID 仅用于本地验证 |
| 折叠屏 | iPhone Duo，iOS 27.3，折叠内屏 466 × 678 pt |
| 其他运行时 | 本机只有 iOS 27.3；未安装 iOS 18 / 26 |
| StoreKit | 本地 `Configuration.storekit`；未连接真实 App Store |

## 2. 构建与静态检查

### 2.1 版本与资源

- `project.yml`：`MARKETING_VERSION = 1.7.1`，`CURRENT_PROJECT_VERSION = 9`。
- `Resources/Localization/Localizable.xcstrings`：426 个 key，zh-Hans / zh-Hant / en / ja 四语言非空。
- `AppShortcuts.xcstrings`：1 个 key；`InfoPlist.xcstrings`：4 个 key。
- Debug scheme 的 LaunchAction 仍绑定 `../../Configuration.storekit`；Release 不启用本地测试商品。
- 新增 `LingXiUITests` target 与 scheme，测试源码位于 `Tests/LingXiUITests`。

### 2.2 本机构建

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/lx171-build build
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/lx171-build build
```

- Debug：**BUILD SUCCEEDED**。
- Release：**BUILD SUCCEEDED**。
- 0 个 Swift 编译错误、0 个 Swift 源码警告；只有 `appintentsmetadataprocessor` 的
  “Metadata extraction skipped, no AppIntents.framework dependency found” 提示。
- 签名模拟器构建：

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=7478C98A-8B78-4B6B-9D25-2B54652D127D' \
  -derivedDataPath /tmp/LX171Sim DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  -allowProvisioningUpdates build
```

  构建成功。不要对 QA 包手动执行 `codesign --deep`，那会抹掉模拟器授权并导致 Keychain 读取失败。

### 2.3 CI 改动

- `.github/actions/setup/action.yml`：选择指定 Xcode，打印版本与运行时，安装固定版本 XcodeGen。
- `.github/workflows/ci.yml`：
  - `policy`：XcodeGen 生成与仓库一致、四语言完整性、StoreKit 配置校验、凭据扫描。
  - `macos-tests`：Xcode 16.4，Kit / Engine / Core 测试。
  - `ios-build-and-test` 矩阵：iOS 18.5（Xcode 16.4）与 iOS 26.0（Xcode 26.3），
    各自执行 Debug / Release generic 构建和 `LingXiPurchaseTests`。
  - 1.7.1 新增“Run conversion, share, and shortcut integration tests”：在模拟器上
    `build-for-testing`，安装 `LingXiIntegrationHost.app`，授权相册读写后
    `test-without-building`。
  - 1.7.1 新增“Run launch smoke test”：`LingXiUITests` 启动 / 首页 / 设置 / Pro 入口。
  - 日志写入 `.build/logs/integration-build.log`、`integration-tests.log`、`ui-smoke.log`。
- 本地已用 Ruby Psych 解析 YAML，并按 CI 的同一顺序预演集成测试：29 / 29 通过。
- 1.7.1 发布验证 GitHub Actions：[run 42435430433](https://github.com/LingXiFox/LingXiStyle/actions/runs/42435430433)，commit `365abf5`，**success**。四个 job 全绿；iOS 18.5 购买 / Keychain 23/23、集成 29/29、UI 冒烟 1/1；iOS 26 购买 / Keychain 24 项执行（23 通过、1 项本地 Offer Code 运行期跳过）、集成 29/29、UI 冒烟 1/1。
- PhotoKit 集成测试此前在 iOS 26 跳过，根因是 `simctl privacy grant photos` 写入 `kTCCServicePhotos.auth_version=1`，PhotoKit 只认 `auth_version=2`；CI 在关机状态把宿主 TCC 行改为 `auth_value=2` / `auth_version=2` 后重启，测试仍要求真实读写权限，权限不生效会失败而不是跳过。`boot-simulator.sh` 为 `bootstatus` 加硬超时与一次重启重试，避免半启动模拟器把 job 卡到 20 分钟超时。
- StoreKitTest 在 iOS 18.5 首次购买冷启动实测 107–571 秒；移除无效的 warm-up，保留 900 秒断言超时，避免把真实挂起误判为通过。

### 2.4 发布资料与隐私清单

- `docs/app-store/listing.md`：zh-Hans / zh-Hant / en / ja 四语言名称、副标题、推广文本、
  关键词、描述与 What's New，字符数均低于 Apple 上限；价格、隐私 URL、支持邮箱、审核联系人、
  备案号均保留占位符，没有编造真实世界信息。
- `docs/privacy/index.html` 与 `docs/support/index.html`：各 4 个语言 section
  （`#zh-Hans` / `#zh-Hant` / `#en` / `#ja`），无 JavaScript、Cookie 或第三方请求。
  `docs/index.html` 的语言导航已补齐对应 `li` id，锚点可用。
- `docs/app-store/screenshots.md`：6.9 英寸 1320 × 2868 规格、6 页清单与四语言截图文案；
  明确禁止使用 `Tests/Fixtures/IMG_5296.HEIC`、合成图或虚构界面。
- `docs/app-store/china-mainland.md`：区分 App 备案与 ICP，列出主体、App、技术、内容材料；
  `<APP_RECORD_NUMBER>` / `<ICP_FILING_NUMBER>` 未取得前不得填写或提交中国大陆区。
- `App/Resources/PrivacyInfo.xcprivacy`：不跟踪、不收集数据、`UserDefaults` / `CA92.1`。
  新增 `ShareExtension/Resources/PrivacyInfo.xcprivacy`：`FileTimestamp` / `C617.1`，
  仅用于清理扩展自身 `LingXiShare-*` 临时目录；扩展未使用 UserDefaults。
- `Tests/Fixtures/IMG_5296.HEIC` 隐私复核：ImageIO / mdls 未发现 GPS、Artist / Owner /
  Copyright、设备序列号或 XMP 作者字段；画面为室外建筑与水面，无特写人脸、证件或私密室内。
  文件仍为 5,924,047 bytes、8064 × 6048、SHA-256
  `7edf1625cc05836dadb1749ad92860abc04ebb21e4848d587cf39cf345c5c2db`，仅用于测试，
  不用于 App Store 截图。

## 3. 模拟器端到端

### 3.1 分享扩展

1.7.0 在 iPhone 17（iOS 27.3）的人工闭环证据：

| 步骤 | 证据 | 结果 |
| --- | --- | --- |
| 从「照片」分享原片到纹粒 | 统一日志 `begin providers=1 types=public.jpeg,public.heic` | ✅ |
| 读取完整 HEIC | `load start identifier=public.heic` → `file callback copied bytes=5924047` | ✅ |
| 进入处理 | `process start bytes=5924047` | ✅ |
| 转换并保存 | 扩展显示“已保存新照片 / 原照片没有被修改” | ✅ |
| 相册新增 | Photos.sqlite 新增 `IMG_0038.HEIC`，文件 5,933,004 字节 | ✅ |
| 额度同步 | 主 App 首页从 4 / 5 变为 3 / 5 | ✅ |
| 分享已处理照片 | 显示“已带有纹理与颗粒 / 无需重复处理”，额度不变 | ✅ |

根因不是 `loadFileRepresentation`：读取回调早已完成并复制了文件，但 `process` 的
`!isBusy` 判断把当前 `reading` 阶段当成忙碌，直接 return，UI 永远停在读取页。
现在只阻止已有 `processingTask`，并新增 3 秒 `loadDataRepresentation` 回退与 15 秒超时
`E_SHARE_READ_TIMEOUT`。

1.7.1 在 `ShareFlowTests` 中用可控 provider 覆盖 12 条路径：成功读取并转换、
读取中取消、转换中取消、无文件、文件表示丢失后 data 回退、15 秒超时、读取失败后重试、
已处理照片不再转换、额度耗尽、相册权限拒绝、损坏 HEIC、第二次 begin 取代第一次读取。
取消路径新增 `cleanupInput()`，不再遗留 `LingXiShare-*` 临时目录。

### 3.2 主 App 转换基线

- 48MP 原片 `IMG_5296.HEIC`：8064 × 6048，54 个主图 tile，15 个 HDR tile。
- 1.2 引擎基线：125 个 item，输出 5,933,004 字节，11 / 11 项无损校验通过；
  两次输出 SHA-256 一致（`90939abf…`），原图 SHA-256 `7edf1625…` 未变。
- 1.7.1 `ConversionIntegrationTests` 使用同一张 48MP fixture（5,924,047 字节，
  SHA-256 `7edf1625cc05836dadb1749ad92860abc04ebb21e4848d587cf39cf345c5c2db`），
  真实执行 inspect → convert → 无损校验 → 写盘，并断言输出仍是 HEIC、原图未变。
- 1.6 / 1.7 模拟器重复保存成功；1.7.1 未改编码核心。

### 3.3 Keychain 共享组与跨进程额度

- 生成的 `LingXiStyle.app-Simulated.xcent` 与 `LingXiStyleShare.appex-Simulated.xcent`
  均包含 `keychain-access-groups = [$(AppIdentifierPrefix)com.lingxifox.LingXiStyle.shared]`。
- 分享扩展转换后主 App 额度同步减少，证明两个进程读写同一账本。
- 1.7.1 集成测试在同一测试进程内用三个独立 `ConversionService` / store 实例验证
  额度预留、提交、跨实例读回、最后额度竞争、Pro 绕过与失败释放。
- `codesign -d --entitlements` 对模拟器产物输出空字典，因此以 `.xcent` 为构建配置证据。
- 真机 distribution 签名下的共享组仍未验证。

### 3.4 Duo 折叠屏

- 1.7.1 build 9 安装于 iPhone Duo，使用
  `xcrun simctl io <UDID> screenshot --display=1 --mask=black` 截取内屏。
- 首页 466 × 678 pt 紧凑布局：额度胶囊 5 / 5、64pt BrandMark、三行说明、狐橙主按钮、
  文件导入与脚注全部可见，无裁切（`/tmp/lx171-duo-home.png`）。
- 设置页原生 Form 完整显示版本 1.7.1 (9)、Pro 行、语言与关于，未溢出
  （`/tmp/lx171-duo-settings.png`）。
- Pro 页标题、权益、购买按钮与法律文案完整；通过 `simctl` 启动未附加 StoreKit 配置，
  商品不可用属预期（`/tmp/lx171-duo-pro.png`）。
- 系统 PhotosPicker 不在 AX 树中，远程输入在首次确认后失效，App 未进入选择页；
  Duo 的选片 / 转换 / 结果页仍未验证，不能记为通过。

## 4. 自动化测试

| Scheme | 结果 | 执行 | 通过 | 跳过 |
| --- | --- | --- | --- | --- |
| `LingXiKitTests` | TEST SUCCEEDED | 28 | 28 | 0 |
| `LingXiPurchaseTests` | TEST SUCCEEDED | 24 | 24 | 0 |
| `LingXiEngineTests` | TEST SUCCEEDED | 2 | 2 | 0 |
| `StylePortCoreTests` | TEST SUCCEEDED | 14 | 12 | 2 |
| `LingXiIntegrationTests` | TEST SUCCEEDED | 29 | 29 | 0 |
| `LingXiUITests` | TEST SUCCEEDED | 1 | 1 | 0 |

本机（iPhone 17 / iOS 27.3）合计执行 98 项，96 项通过，2 项因缺少外部 fixture 跳过。
CI 的 iOS 18.5 与 26.x 集成测试均 29 项执行 / 0 跳过 / 0 失败；两条此前的 PhotoKit 保存测试已实际执行。

CI 运行时差异（同一份测试代码，1.7.0 结果）：

| CI job | 系统 / Xcode | 购买测试 | 说明 |
| --- | --- | --- | --- |
| `iOS 18.5 compatibility` | iPhone 16 模拟器 / Xcode 16.4 | 23 执行，23 通过 | `.codeOffer` 测试由 `#if compiler(>=6.2)` 排除；Ask to Buy 走已验证权益恢复分支 |
| `iOS 26.x current` | iPhone 16 模拟器 / iOS 26.0（26.0.1）/ Xcode 26.3 | 24 执行，23 通过，1 跳过 | iOS 26 StoreKitTest 不应用本地 Offer Code，测试明确 `XCTSkip`，不是放行失败 |

本机 iOS 27.3 的 Offer Code 测试实际执行并通过（0 元交易、验签、授予 Pro）。

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiPurchaseTests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiIntegrationTests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiUITests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
```

集成测试运行前必须给宿主授权：

```bash
xcrun simctl privacy booted grant photos com.lingxifox.LingXiStyle.IntegrationHost
xcrun simctl privacy booted grant photos-add com.lingxifox.LingXiStyle.IntegrationHost
```

### 4.1 LingXiKitTests（28）

- `ISOBoxTests`（2）：ISO BMFF 同级 box 解析、尾部填充容忍。
- `HEIFReferenceTests`（3）：`iref` 16-bit / 32-bit ID；损坏条目只产生 warning。
- `CompatibilityTests`（5）：完整 HEIC 可添加；已编辑资产提示后仍可转换；Live Photo 拒绝；
  已含纹理与颗粒不重复处理；非 HEIF 只报容器问题。
- `ConversionRunTests`（7）：已保存项不重复转换；取消保留已完成项；未开始即取消；
  旧 session token 不能完成新会话；unsupported / unavailable 不阻塞后续项；旧完成回调被忽略；
  跨入口抢最后额度时已保存项不变，其余 pending 转 deferred。
- `QuotaTests`（11）：初始 5 / 5；成功扣减；释放不扣；提交幂等；第 5 张耗尽、第 6 张拒绝；
  自然日重置；耗尽拒绝；两进程抢最后一槽；跨实例读回；Pro 绕过；过期预留回收。

### 4.2 LingXiPurchaseTests（24）

`StoreKitPurchaseTests`（14）：

1. 本地配置加载非消耗型商品，Product ID 与显示名正确。
2. USA / CHN / JPN / DEU 四个 storefront 的价格来自 StoreKit，货币符号与
   `priceFormatStyle.currencyCode` 一致，且四个价格不全相同（证明未硬编码）。
3. 成功购买后 `PurchaseManager.isPro` 与 `StoreKitEntitlementProvider.isPro()` 同时为真。
4. 用户取消不授予 Pro，不留下 `.purchased` / `.restored` 交易。iOS 18 / 26 的
   StoreKitTest 会在 `allTransactions()` 保留非成功尝试，因此断言只统计已完成交易。
5. 网络失败显示错误，不授予 Pro，不留下已完成交易。
6. 交易 pending 时不授予；批准后由交易监听解锁。iOS 18.5 的 StoreKitTest 不把批准事件
   送进 `Transaction.updates`，测试改为验证已验签权益并调用 `refreshEntitlement()` 恢复；
   iOS 26 / 27 仍验证真实监听回调。
7. 恢复购买恢复 Pro。
8. 重启后仍能读取已验签交易。
9. 退款 / 撤销后 Pro 失效，回到免费额度。
10. 重复交易回调不会重复授予。
11. 商品加载失败提供友好错误与重试入口。
12. 共享额度：三个 `ConversionService` 实例使用同一账本，任意入口提交后其余入口立即看到已用 1 张。
13. 失败转换不扣额度：损坏 HEIC 在预检阶段失败，记录一次预留与一次释放、零提交，额度仍为 5 / 5。
14. **免费 Offer Code**：`.codeOffer(referenceName: "DEVELOPER_FREE")` 购买成功，
    交易价格为 0，无撤销 / 过期，`StoreKitEntitlementProvider.isPro()` 为真，新
    `PurchaseManager` 启动即为 Pro。Xcode 16.4 没有 `.codeOffer` API，编译期排除；
    iOS 26 StoreKitTest 仍按 2.99 收款，运行期 `XCTSkip`；本机 iOS 27.3 实际执行通过。
    生产兑换仍必须使用 App Store Connect 的官方 Offer Code。

`KeychainQuotaTests`（10）：

1. 默认额度为 5 张。
2. reserve / commit / release 只占一个槽。
3. commit 幂等；迟到的 release 不能抹掉已提交额度。
4. 两个独立 store 竞争最后 1 个槽，只有一个成功。
5. 超过 30 分钟的预留会被回收。
6. 本地自然日切换后额度重置。
7. 新建 store 实例仍能读到已提交记录（模拟进程重启）。
8. Pro 完全绕过 Keychain 账本。
9. **fail-closed**：配置了共享组但进程没有对应 entitlement 时，`status(isPro:)` 抛
   `QuotaError.database`，不会静默回退到另一套 Keychain 条目。
10. **access group 解析**：nil / 空串 / 纯空白 / 未展开的 `$(` 返回 nil；
    合法值去除首尾空白后返回。

StoreKit 授权只接受 `.verified` 交易；未验签、pending、取消、网络失败都不会写入 Pro 状态。

### 4.3 LingXiEngineTests（2）

- JPEG 输入拒绝，错误码 `E_UNSUPPORTED:notHEIC`。
- 输出名稳定为 `IMG_0001_TextureGrain.heic`，重复处理不叠加后缀。

### 4.4 StylePortCoreTests（14，2 跳过）

上游编码核心的结构测试。跳过的 2 项依赖 `STYLEPORT_FIXTURES` / `STYLEPORT_LIVE_VIDEO`
环境变量，未配置，不是失败。

### 4.5 LingXiIntegrationTests（29）

`ConversionIntegrationTests`（8）：

1. fixture 的 SHA-256 与文档记录一致。
2. 真实 48MP HEIC 通过兼容性检查，状态为 ready。
3. 真实转换产出可解析的 HEIC，主图校验通过，原图字节未变。
4. 额度在独立 `ConversionService` 与 `QuotaManager` 实例间持久化。
5. 损坏输入不扣额度。
6. 已处理输出不扣额度。
7. Pro 转换不触碰免费账本。
8. 转换后写入 PhotoKit 并回读为 HEIC（测试会保留新增相册资源，避免系统删除确认阻塞）。

`ShareFlowTests`（12）：成功读取并转换；读取中取消；转换中取消；provider 无文件；
文件表示丢失后 data 回退；15 秒超时；读取失败后重试复用 provider；已处理照片跳过；
额度耗尽；相册权限拒绝；损坏 HEIC；第二次 begin 取代第一次读取。

`ShortcutIntegrationTests`（9）：单张返回 HEIC 并扣 1 格；同名两张各自输出；
仅检查不转换不扣额度；仅保存不返回文件但写入相册；损坏输入跳过不扣额度；Pro 不触碰免费账本；
额度耗尽停止批次并报告未处理项；跳过项不转换；缺少输入 / 输出被拒绝。

### 4.6 LingXiUITests（1）

`HomeSmokeTests.testHomeSettingsAndProEntryPoints`：以英文启动，断言首页根视图与
选择照片、文件导入、设置、额度四个入口；打开设置，点击 Pro 行，断言 `Texel Pro`，
关闭 Pro 页并返回首页。只验证安装、启动与入口，不伪造转换结果。

## 5. 1.7.1 实现审查

| 项 | 验证方式 | 结论 |
| --- | --- | --- |
| Xcode 16.4 编译失败 | 源码 + CI 构建 | ✅ 移除对 `StoreKitError.invalidPresentationContext` 的直接匹配；旧 SDK 不再报 `_ErrorCodeProtocol` 错误 |
| Xcode 16.4 类型检查超时 | 源码 + CI 构建 | ✅ `PeopleDetection` 的 `matteSize`、`RasterImport` 的 `appleExif` 与 Core 测试 fixture 拼接拆分，旧编译器通过 |
| CI 设计 | GitHub Actions + 本地 YAML 解析 | ✅ 双 SDK 矩阵、策略检查、macOS 单测、集成测试与启动冒烟已接入；1.7.1 run 42435430433 四个 job 全绿，PhotoKit TCC auth_version 与模拟器启动超时已修复 |
| 分享扩展阻塞 | 源码 + 统一日志 + 模拟器闭环 | ✅ `process` 不再把 `reading` 当忙碌；读取、转换、保存、额度同步全部通过 |
| 分享读取超时 / 回退 | 自动化 | ✅ 3 秒 data fallback、15 秒 deadline、`E_SHARE_READ_TIMEOUT`；12 条状态机测试通过 |
| 分享取消 / 重试 | 自动化 | ✅ 取消递增 generation，清理回退 / 超时任务；取消时删除 `LingXiShare-*` 临时目录 |
| Keychain 共享组 | 签名模拟器构建 + `.xcent` | ✅ App / 扩展同一组，额度跨进程同步；真机 distribution 未验 |
| Keychain fail-closed | 自动化 | ✅ 无权限时抛 `QuotaError.database` |
| 免费 Offer Code | StoreKitTest | ✅ 0 元交易验签后授予 Pro；生产发放仍需 App Store Connect |
| 商品价格 | 自动化 + 模拟器 | ✅ 本地配置 `$2.99`；实际 UI 走 `Product.displayPrice` |
| 额度唯一入口 | 源码 + 自动化 | ✅ App / 分享扩展 / 快捷指令均走 `ConversionService` |
| 真实端到端 | 集成测试 | ✅ 真实 48MP HEIC、真实 PhotoKit 保存、真实 Keychain 扣减 |
| 启动冒烟 | XCUITest | ✅ 安装、启动、首页、设置、Pro 入口 |
| Duo 紧凑布局 | 签名构建 + 内屏截图 | ✅ 首页 / 设置 / Pro 无裁切；选片未验证 |
| 版本 1.7.1 / build 9 | `project.yml` + 构建产物 | ✅ |
| 1.5 视觉基线 | 1.6 / 1.7 / 1.7.1 截图 | ✅ 未改视觉层；狐橙 `#E8A13A`、iOS 语义表面 |

## 6. 兼容性矩阵

状态：✅ 已验证；🟡 已构建，但未跑完整业务；⚪ 未验证。

| 系统 | 设备 / 环境 | 构建 | 启动 | 主流程 | 已知问题 | 验证方式 |
| --- | --- | --- | --- | --- | --- | --- |
| iOS 18.0 | 无 | 🟡 以 iOS 18.5 SDK、部署目标 18.0 编译 | ⚪ | ⚪ | 无运行时；最低版本只有编译覆盖，不等于运行兼容 | CI `ios-18` |
| iOS 18.5 | CI iPhone 16 模拟器 | ✅ | ✅ | ⚪ | Debug / Release + 23 项购买 / Keychain + 29 项集成（0 跳过）+ 1 项 UI 冒烟通过；完整 UI 主流程未人工操作 | CI `ios-18` |
| iOS 18.6 | CI 运行器已安装但未选中 | ⚪ | ⚪ | ⚪ | 未构建、未运行 | 未执行 |
| iOS 26.0（26.0.1） | CI iPhone 16 模拟器 | ✅ | ✅ | ⚪ | Debug / Release + 24 项测试（23 通过、1 项本地 Offer Code 运行期跳过）+ 29 项集成（0 跳过）+ 1 项 UI 冒烟通过；完整 UI 主流程未人工操作 | CI `ios-26` |
| iOS 26.1 | CI 运行器已安装但未选中 | ⚪ | ⚪ | ⚪ | 未构建、未运行 | 未执行 |
| iOS 26.2 | CI 运行器已安装但未选中 | ⚪ | ⚪ | ⚪ | 未构建、未运行 | 未执行 |
| iOS 27.0 – 27.2 | 无 | ⚪ | ⚪ | ⚪ | 本机无对应运行时 | 未执行 |
| iOS 27.3 | iPhone 17 模拟器 | ✅ | ✅ | ✅ 选图 / 转换 / 保存 / 分享扩展 | 见第 7 节限制 | 本机签名构建 + 目视 + 统一日志 + 自动化 |
| iOS 27.3 | iPhone Duo 模拟器（466 × 678 pt） | ✅ | ✅ | 🟡 首页 / 设置 / Pro 通过；选片未进入 | 系统 PhotosPicker 远程输入失效，非已证 App 缺陷 | 内屏截图 + AX 树 |

iOS 18 / 26 的启动和主流程没有在本机执行，不能因为 CI 编译通过就写成兼容性通过。
主 App 的 HEIF 结构处理与系统版本相关性仍需真机样本确认。

## 7. 已知风险与未验证项

1. **没有真机安装。** 所有结果来自模拟器与自动化测试；真机 entitlements、相册权限、
   分享扩展生命周期、7 天签名到期都未验证。
2. **没有真实 App Store 交易。** `SKTestSession` 与本地 `.storekit` 不能证明生产商品、
   税务 / 银行、Sandbox 账号、退款到账时延。上线前必须按 `AppStoreRelease.md` 走 Sandbox。
3. **Offer Code 只在本地配置验证。** 本机 iOS 27.3 的 0 元交易能被正确授予 Pro；
   iOS 18 / 26 的本地 StoreKitTest 不支持该配置（一个被旧编译器排除，一个运行期跳过）。
   生产环境的 Offer Code 需要商品可发放、App 已发布或符合 Apple 的兑换条件，
   且必须在 App Store Connect 创建。
4. **iOS 18 / 26 覆盖构建、购买 / Keychain 与集成测试，但不等同完整系统兼容。** 本机没有对应运行时，启动、主流程、PhotosPicker、分享扩展 UI 与 UI 适配未在这些系统上运行；不能因为 CI 编译通过就写成系统兼容通过。
5. **分享扩展 UI 只人工验证成功与已处理。** 取消、15 秒超时、非 HEIC、额度耗尽、
   相册写入失败由状态机测试覆盖，未逐项在扩展 UI 中构造。
6. **快捷指令未运行 UI。** 9 条集成测试覆盖参数、批量、仅检查、仅保存、额度与 Pro；
   Shortcuts App 中的实际参数面板与返回文件未人工操作。
7. **权限拒绝页未目视。** `simctl privacy` 无法稳定把流程推进到 `.permissionDenied`。
8. **系统矩阵仍空白。** 12MP / 24MP、夜景、人像、RAW、iCloud 下载、存储不足、
   批量取消 / 重试未在真机验收。
9. **Duo 只验证首页 / 设置 / Pro。** 选片输入在模拟器中失效，转换与结果页未验证。
10. `StylePortCoreTests` 有 2 项跳过，因为未设置 `STYLEPORT_FIXTURES` /
    `STYLEPORT_LIVE_VIDEO`，不是代码失败。
11. 免费 Personal Team 签名 7 天过期，属预期限制。
12. Keychain 账本用固定槽位表达每日额度；卸载重装不保证重置，本版本不会主动清除服务
    `com.lingxifox.LingXiStyle.quota`。
13. 本地 StoreKit 配置的 `$2.99` 仅用于测试；配置保留德文商品本地化，但 App UI 只有
    zh-Hans / zh-Hant / en / ja。
14. 通过 `simctl launch` 启动不会附加 `Configuration.storekit`，Pro 页可能显示商品不可用；
    这是真实的加载失败路径，不代表线上商品缺失。

## 8. GitHub Actions

- 工作流：`.github/workflows/ci.yml`
- 1.7.1 发布验证：[run 42435430433](https://github.com/LingXiFox/LingXiStyle/actions/runs/42435430433)
  （commit `365abf5`）— **success**。
  - `Policy and project checks`：成功；XcodeGen 一致、四语言、StoreKit 配置、凭据扫描通过。
  - `macOS unit tests`：成功；Kit 28、Engine 2、Core 14（2 跳过）。
  - `iOS 18.5 compatibility`：成功；Debug / Release 构建通过，购买 / Keychain 23/23，
    集成 29 项执行 / 0 跳过 / 0 失败，UI 冒烟 1/1。
  - `iOS 26.x current`：成功；Debug / Release 构建通过，购买 / Keychain 24 项执行 /
    23 通过 / 1 项本地 Offer Code 运行期跳过，集成 29 项执行 / 0 跳过 / 0 失败，UI 冒烟 1/1。
  - 两条 iOS job 的 `testConvertAndSaveToPhotoLibrary` 与 `testSaveOnlyDoesNotReturnAFileButDoesSave`
    均已实际执行并通过，不再跳过。
- 1.7.0 完整运行（历史）：[run 42371186297](https://github.com/LingXiFox/LingXiStyle/actions/runs/42371186297)
  （commit `24bfa3c`）— **success**。
  - `Policy and project checks`：成功；XcodeGen 一致、四语言、StoreKit 配置、凭据扫描通过。
  - `macOS unit tests`：成功；Kit 28、Engine 2、Core 14（2 跳过）。
  - `iOS 18.5 compatibility`：成功；Debug / Release 构建通过，23 项购买 / Keychain 测试通过。
  - `iOS 26.x current`：成功；在 iPhone 16 / iOS 26.0（26.0.1）上 Debug / Release 构建通过，
    24 项中 23 通过、1 项 Offer Code 因运行时限制跳过。该 job 没有覆盖 26.1 / 26.2。
- 前几轮失败已修复：`ProEntitlement.swift` 的 `invalidPresentationContext` 编译错误、
  `PeopleDetection` / `RasterImport` / Core 测试 fixture 在 Xcode 16.4 的类型检查超时，
  以及 StoreKitTest 在 iOS 18 / 26 对取消 / 失败交易和 Ask to Buy 的差异断言。
- 运行器提示：`actions/checkout@v4` 使用 Node.js 20 已弃用（GitHub 强制 Node.js 24），
  不影响本次结果。

## 9. 建议的验收顺序

1. 用付费团队或 Personal Team 在真机安装 1.7.1，确认首页显示 5 / 5，首次启动不弹付费页。
2. 转换 1 张，确认扣到 4 / 5；杀掉 App 重开，确认仍为 4 / 5。
3. 用分享扩展转换 1 张，回到主 App 确认额度同步减少（真机跨进程关键项）。
4. 用损坏 HEIC、JPEG、Live Photo、已含纹理与颗粒照片各试一次，确认全部不扣额度。
5. 连续转换到第 6 张，确认首次用尽只自动弹一次 Pro；再用 3 张批量但只剩 1 张额度，
   确认只转 1 张，结果页文案正确。
6. 在 Sandbox 购买 Pro，确认首页切换为无限、重启保持；再测恢复购买与退款。
7. 在 App Store Connect 创建 100% Offer Code，用 Sandbox 账号兑换，确认
   `Transaction.currentEntitlements` 出现 Pro 且可恢复。
8. 在 Duo 真机或可交互模拟器上完成选片 / 转换 / 结果页，补上折叠屏主流程证据。
