# 测试报告（纹粒 / Texel 1.7.0）

- 日期：2026-11-07
- 版本：1.7.0（build 8）
- 结论：本机 Debug / Release 构建、四套自动化测试与 iOS 27.3 模拟器分享闭环通过；
  iOS 18.5 / 26.x 由 GitHub Actions 矩阵覆盖编译与 StoreKit 测试，但本机没有对应运行时；
  真机、真实 App Store 交易与部分失败路径仍未验证。本报告只记录实际执行过的证据。

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
| 其他运行时 | 本机只有 iOS 27.3；未安装 iOS 18 / 26 |
| StoreKit | 本地 `Configuration.storekit`；未连接真实 App Store |

## 2. 构建与静态检查

### 2.1 版本与资源

- `project.yml`：`MARKETING_VERSION = 1.7.0`，`CURRENT_PROJECT_VERSION = 8`。
- `Resources/Localization/Localizable.xcstrings`：425 个 key，zh-Hans / zh-Hant / en / ja 四语言非空。
- `AppShortcuts.xcstrings`：1 个 key；`InfoPlist.xcstrings`：4 个 key。
- Debug scheme 的 LaunchAction 仍绑定 `../../Configuration.storekit`；Release 不启用本地测试商品。

### 2.2 本机构建

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/LX17BuildDD build
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/LX17BuildDD build
```

- Debug：**BUILD SUCCEEDED**。
- Release：**BUILD SUCCEEDED**。
- 0 个 Swift 编译错误；只有 `appintentsmetadataprocessor` 的
  “Metadata extraction skipped, no AppIntents.framework dependency found” 提示。
- 签名模拟器构建：

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'platform=iOS Simulator,id=7478C98A-8B78-4B6B-9D25-2B54652D127D' \
  -derivedDataPath /tmp/LX17Keychain DEVELOPMENT_TEAM=4VXWMYSQG8 \
  -allowProvisioningUpdates build
```

  构建成功。不要对 QA 包手动执行 `codesign --deep`，那会抹掉模拟器授权并导致 Keychain 读取失败。

### 2.3 CI 改动

- `.github/actions/setup/action.yml`：选择指定 Xcode，打印版本与运行时，安装固定版本 XcodeGen。
- `.github/workflows/ci.yml`：
  - `policy`：XcodeGen 生成与仓库一致、四语言完整性、StoreKit 配置校验、凭据扫描。
  - `macos-tests`：Xcode 16.4，Kit / Engine / Core 测试。
  - `ios-build-and-test` 矩阵：iOS 18.5（Xcode 16.4）与 iOS 26.x（Xcode 26.3），
    各自执行 Debug / Release generic 构建和 `LingXiPurchaseTests`。
- StoreKit 配置校验要求：唯一非消耗型商品 `com.lingxifox.LingXiStyle.pro`、本地测试价
  `2.99`、Offer Code `DEVELOPER_FREE` 为 0 元、`_developerTeamID` 为空。

## 3. 模拟器端到端

### 3.1 分享扩展

环境：iPhone 17，iOS 27.3，签名模拟器构建。

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

### 3.2 主 App 转换基线

- 48MP 原片 `IMG_5296.HEIC`：8064 × 6048，54 个主图 tile，15 个 HDR tile。
- 1.2 引擎基线：125 个 item，输出 5,933,004 字节，11 / 11 项无损校验通过；
  两次输出 SHA-256 一致（`90939abf…`），原图 SHA-256 `7edf1625…` 未变。
- 1.6 / 1.7 模拟器重复保存成功；1.7 未改编码核心。

### 3.3 Keychain 共享组

- 生成的 `LingXiStyle.app-Simulated.xcent` 与 `LingXiStyleShare.appex-Simulated.xcent`
  均包含 `keychain-access-groups = [4VXWMYSQG8.com.lingxifox.LingXiStyle.shared]`。
- 分享扩展转换后主 App 额度同步减少，证明两个进程读写同一账本。
- `codesign -d --entitlements` 对模拟器产物输出空字典，因此以 `.xcent` 为构建配置证据。
- 真机 distribution 签名下的共享组仍未验证。

## 4. 自动化测试

| Scheme | 结果 | 执行 | 通过 | 跳过 |
| --- | --- | --- | --- | --- |
| `LingXiKitTests` | TEST SUCCEEDED | 28 | 28 | 0 |
| `LingXiPurchaseTests` | TEST SUCCEEDED | 24 | 24 | 0 |
| `LingXiEngineTests` | TEST SUCCEEDED | 2 | 2 | 0 |
| `StylePortCoreTests` | TEST SUCCEEDED | 14 | 12 | 2 |

合计执行 68 项，66 项通过，2 项因缺少外部 fixture 跳过。

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiPurchaseTests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
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
4. 用户取消不授予 Pro，不产生交易。
5. 网络失败显示错误，不授予 Pro。
6. 交易 pending 时不授予；批准后由交易监听解锁。
7. 恢复购买恢复 Pro。
8. 重启后仍能读取已验签交易。
9. 退款 / 撤销后 Pro 失效，回到免费额度。
10. 重复交易回调不会重复授予。
11. 商品加载失败提供友好错误与重试入口。
12. 共享额度：三个 `ConversionService` 实例使用同一账本，任意入口提交后其余入口立即看到已用 1 张。
13. 失败转换不扣额度：损坏 HEIC 在预检阶段失败，记录一次预留与一次释放、零提交，额度仍为 5 / 5。
14. **1.7 新增免费 Offer Code**：`.codeOffer(referenceName: "DEVELOPER_FREE")` 购买成功，
    交易价格为 0，无撤销 / 过期，`StoreKitEntitlementProvider.isPro()` 为真，新
    `PurchaseManager` 启动即为 Pro。该测试在 Xcode 16.4 上因 SDK 无 `.codeOffer` 而编译跳过，
    当前 SDK（Xcode 27.3）执行。

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
10. **1.7 新增 access group 解析**：nil / 空串 / 纯空白 / 未展开的 `$(` 返回 nil；
    合法值去除首尾空白后返回。

StoreKit 授权只接受 `.verified` 交易；未验签、pending、取消、网络失败都不会写入 Pro 状态。

### 4.3 LingXiEngineTests（2）

- JPEG 输入拒绝，错误码 `E_UNSUPPORTED:notHEIC`。
- 输出名稳定为 `IMG_0001_TextureGrain.heic`，重复处理不叠加后缀。

### 4.4 StylePortCoreTests（14，2 跳过）

上游编码核心的结构测试。跳过的 2 项依赖 `STYLEPORT_FIXTURES` / `STYLEPORT_LIVE_VIDEO`
环境变量，未配置，不是失败。

## 5. 1.7 实现审查

| 项 | 验证方式 | 结论 |
| --- | --- | --- |
| Xcode 16.4 编译失败 | 源码 + CI 构建 | ✅ 移除对 `StoreKitError.invalidPresentationContext`（iOS 27 SDK 才有的 case）的直接匹配，改用 if-case 分支；旧 SDK 不再报 `_ErrorCodeProtocol` 错误 |
| Xcode 16.4 类型检查超时 | 源码 + CI 构建 | ✅ `Core/Sources/StylePortCore/PeopleDetection.swift` 的 `matteSize` 拆成 `ratio` / `scaled` 两步，`Core/Sources/StylePortCore/RasterImport.swift` 的 `appleExif` 字节拼接拆成多次 `+=`；旧编译器不再报 `unable to type-check this expression in reasonable time` |
| CI 设计 | `.github/workflows/ci.yml` + 本地 YAML 解析 | 🟡 双 SDK 矩阵、策略检查与产物上传已写入；首轮 GitHub 运行结果见第 8 节 |
| 分享扩展阻塞 | 源码 + 统一日志 + 模拟器闭环 | ✅ `process` 不再把 `reading` 当忙碌；读取、转换、保存、额度同步全部通过 |
| 分享读取超时 / 回退 | 源码审查 | ✅ 3 秒 data fallback、15 秒 deadline、`E_SHARE_READ_TIMEOUT`；超时 UI 未实测 |
| 分享取消 / 重试 | 源码审查 | ✅ 取消递增 generation，清理回退 / 超时任务；重试可复用已保留 provider；未实测 |
| 分享临时目录 | 源码审查 | ✅ 只清理 1 小时前的 `LingXiShare-*`，关闭时清理当前目录 |
| Keychain 共享组 | 签名模拟器构建 + `.xcent` | ✅ App / 扩展同一组，额度跨进程同步；真机 distribution 未验 |
| Keychain fail-closed | 自动化 | ✅ 无权限时抛 `QuotaError.database` |
| 免费 Offer Code | StoreKitTest | ✅ 0 元交易验签后授予 Pro；生产发放仍需 App Store Connect |
| 商品价格 | 自动化 + 模拟器 | ✅ 本地配置 `$2.99`；实际 UI 走 `Product.displayPrice` |
| 额度唯一入口 | 源码 + 自动化 | ✅ App / 分享扩展 / 快捷指令均走 `ConversionService` |
| 版本 1.7.0 / build 8 | `project.yml` + 构建产物 | ✅ |
| 1.5 视觉基线 | 1.6 / 1.7 截图 | ✅ 未改视觉层；狐橙 `#E8A13A`、iOS 语义表面 |

## 6. 兼容性矩阵

状态：✅ 已验证；🟡 已构建，但未跑完整业务；⚪ 未验证。

| 系统 | 设备 / 环境 | 构建 | 启动 | 主流程 | 已知问题 | 验证方式 |
| --- | --- | --- | --- | --- | --- | --- |
| iOS 18.0 | 无 | 🟡 部署目标，CI 用 18.5 SDK 编译 | ⚪ | ⚪ | 无运行时；最低版本仅编译覆盖 | CI `ios-18` |
| iOS 18.5 | CI iPhone 16 模拟器 | 🟡 | ⚪ | ⚪ | 仅构建 + StoreKit 单测 | CI `ios-18` |
| iOS 26.0 – 26.2 | CI iPhone 16 / 17 模拟器 | 🟡 | ⚪ | ⚪ | 仅构建 + StoreKit 单测 | CI `ios-26` |
| iOS 27.0 – 27.2 | 无 | ⚪ | ⚪ | ⚪ | 本机无对应运行时 | 未执行 |
| iOS 27.3 | iPhone 17 模拟器 | ✅ | ✅ | ✅ 选图 / 转换 / 保存 / 分享扩展 | 见第 7 节限制 | 本机签名构建 + 目视 + 统一日志 |

iOS 18 / 26 的启动和主流程没有在本机执行，不能因为 CI 编译通过就写成兼容性通过。
主 App 的 HEIF 结构处理与系统版本相关性仍需真机样本确认。

## 7. 已知风险与未验证项

1. **没有真机安装。** 所有结果来自模拟器与单元测试；真机 entitlements、相册权限、
   分享扩展生命周期、7 天签名到期都未验证。
2. **没有真实 App Store 交易。** `SKTestSession` 与本地 `.storekit` 不能证明生产商品、
   税务 / 银行、Sandbox 账号、退款到账时延。上线前必须按 `AppStoreRelease.md` 走 Sandbox。
3. **Offer Code 只在本地配置验证。** 0 元交易能被正确授予 Pro；生产环境的 Offer Code
   需要商品可发放、App 已发布或符合 Apple 的兑换条件，且必须在 App Store Connect 创建。
4. **iOS 18 / 26 只覆盖编译与 StoreKit 测试。** 本机没有对应运行时，主流程、
   PhotosPicker、分享扩展与 UI 适配未在这些系统上运行。
5. **分享扩展只验证了成功与已处理两条路径。** 取消、15 秒超时、非 HEIC、额度耗尽、
   相册写入失败没有在 UI 上逐一构造。
6. **快捷指令未运行 UI。** 代码共用 `ConversionService`，但 AppIntents 参数、
   返回文件与跨进程额度未在 Shortcuts 中实测。
7. **权限拒绝页未目视。** `simctl privacy` 无法稳定把流程推进到 `.permissionDenied`。
8. **系统矩阵仍空白。** 12MP / 24MP、夜景、人像、RAW、iCloud 下载、存储不足、
   批量取消 / 重试未在 1.7 真机验收。
9. **Duo 只验证了 1.6 首页。** 1.7 没有重新跑折叠屏选片 / 转换。
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
- 首次 1.7 运行：**待推送后补充运行链接与结果**。
- 上一轮失败：run 42365742133 的 `Build Debug for iOS` 因
  `ProEntitlement.swift:195` 的 `invalidPresentationContext` 编译错误失败；该行已修复。

## 9. 建议的验收顺序

1. 用付费团队或 Personal Team 在真机安装 1.7，确认首页显示 5 / 5，首次启动不弹付费页。
2. 转换 1 张，确认扣到 4 / 5；杀掉 App 重开，确认仍为 4 / 5。
3. 用分享扩展转换 1 张，回到主 App 确认额度同步减少（真机跨进程关键项）。
4. 用损坏 HEIC、JPEG、Live Photo、已含纹理与颗粒照片各试一次，确认全部不扣额度。
5. 连续转换到第 6 张，确认首次用尽只自动弹一次 Pro；再用 3 张批量但只剩 1 张额度，
   确认只转 1 张，结果页文案正确。
6. 在 Sandbox 购买 Pro，确认首页切换为无限、重启保持；再测恢复购买与退款。
7. 在 App Store Connect 创建 100% Offer Code，用 Sandbox 账号兑换，确认
   `Transaction.currentEntitlements` 出现 Pro 且可恢复。
