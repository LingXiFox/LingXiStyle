# TEST_REPORT

- 日期：2026-11-07
- 项目：LingXiStyle 1.2.0（build 3）
- 结论：**XcodeGen 生成、Debug / Release 构建与全部自动化测试通过。1.2 在 iPhone 17 模拟器（iOS 27.3）完成 48MP HEIC 端到端转换，免费额度从 10/10 扣到 9/10，终止进程重启后仍为 9/10；额度耗尽页与 Pro 升级切换已目视通过，本地 StoreKit 购买成功且重启后保持 Pro。真实 App Store 交易、真机、分享扩展与快捷指令的额度共享仍需验收。**

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.3（26C5035r），Apple Silicon |
| Xcode | 27.3（27C5020n），MacOSX27.3.sdk |
| Swift | Swift 5 语言模式（`SWIFT_VERSION=5.0`） |
| 部署目标 | iOS 18.0 |
| 工程生成 | XcodeGen 2.46.0 |
| 签名 | 自动签名；本轮 QA 使用开发者本机 Apple Development Team，仓库不包含 Team ID |
| 模拟器 | iPhone 17，iOS 27.3；已运行 1.2 主流程、免费额度持久化、额度耗尽、Pro 购买与重启恢复、浅色页面 |
| 真机 | 1.0 曾在 iPhone 16 Pro Max 安装运行；1.2 未做真机安装 |
| StoreKit | 本地 `Configuration.storekit`；没有连接 App Store，没有真实扣款 |

## 2. 构建结果

### 2.1 工程生成与版本

`xcodegen generate` 成功。App 与 ShareExtension 的 Info.plist 均使用
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`，本轮版本为
**1.2.0 / build 3**。

`LingXiStyle.xcscheme` 的 LaunchAction 含：

```xml
<StoreKitConfigurationFileReference identifier = "../../Configuration.storekit">
```

本地 StoreKit 配置只绑定 Debug scheme；Release 不读取该文件。

### 2.2 Debug 与 Release

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

结果：**Debug BUILD SUCCEEDED；Release BUILD SUCCEEDED**，0 error、0 Swift compiler warning。
只有 `appintentsmetadataprocessor` 的非阻塞提示，不影响 App 的 `Metadata.appintents`。

产物包含 `LingXiStyle.app`、`PlugIns/LingXiStyleShare.appex`、嵌入的
`LingXiKit.framework` / `LingXiEngine.framework` / `LingXiServices.framework` /
`StylePortCore.framework`，以及 `Metadata.appintents`。

### 2.3 签名模拟器构建

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/LingXiStyle-FinalSim \
  DEVELOPMENT_TEAM=<your team> -allowProvisioningUpdates build
```

结果 **BUILD SUCCEEDED**，App 安装并在 iPhone 17 模拟器启动。

> 该 QA 构建由 Xcode 自动签名，entitlements 为空，Keychain 额度仍可读写。
> 不要对 QA 产物手工执行 `codesign --deep`：手工重签会破坏 Keychain 访问，之前的
> 额度读取失败由此引起，不是 App 逻辑问题。

### 2.4 1.2 模拟器端到端验收

设备：iPhone 17 模拟器，iOS 27.3；样本为 8064 × 6048（48MP）iPhone 实拍 HEIC，
125 items、54 个主图 tile、15 个 HDR gain-map tile。

| 步骤 | 结果 |
| --- | --- |
| 首次进入首页 | 显示「今日剩余 10 / 10 张」；未弹付费页 |
| PhotosPicker 选片 | 兼容标签「可解锁」；显示 8,064 × 6,048、54 个主图分块、HDR |
| 转换 | 约 1.2 秒完成；真实阶段文字与进度；结果页「成功 1 张」「已保存新照片」 |
| 保存回读 | 新 HEIC 保存成功；原图未被覆盖；11/11 无损校验通过 |
| 额度扣减 | 返回首页显示「今日剩余 9 / 10 张」 |
| 进程重启 | `simctl terminate` 后重新启动，仍显示「今日剩余 9 / 10 张」 |
| 输出再选择 | 已转换的 `IMG_5296_TextureGrain.heic` 显示「无需转换」 |
| 空状态 | 浅色下品牌标题、构图框、两个入口与「仅在本机处理 · 原图始终保留」同屏可见 |
| Pro 页面 | 从额度徽标打开；显示本地配置价格 `$4.99`、权益列表、购买按钮；购买 CTA 在首屏可见，恢复购买与法律说明在下方滚动 |
| 额度耗尽页 | 临时把免费上限调为 1（已有 9 张用量），首页显示「今日免费额度已用完」；选片后 CTA 打开耗尽页，显示「明天恢复 1 张」、永久解锁与明天继续两个出口；已还原为 10 |
| 耗尽页 → Pro | 点「永久解锁无限转换」后同一 sheet 内切换为 Pro 页面；价格、购买按钮、恢复购买均可见 |
| 本地购买 | 显示 Xcode 测试环境提示「You will not be charged」；确认后出现「已解锁 LingXiStyle Pro」，首页徽标变为「LingXiStyle Pro · 无限转换」 |
| 购买后重启 | `simctl terminate` 后启动，仍显示 Pro 无限；点 Pro 徽标可重新打开 Pro 页面 |

本地 StoreKit 配置的 `$4.99` 只用于自动化与模拟器，**不是线上价格**；线上价格必须来自
App Store Connect 的 `Product.displayPrice`。

### 2.5 真实 HEIC 引擎基线（1.0 验证，1.2 未改算法）

- 输入 8064 × 6048 HEIC，125 items、54 主图 tiles、15 HDR tiles。
- `ConversionEngine.convert` 返回 `mode=add-texture`；输出 5,933,004 字节，
  `texture=added #151 -> [55, 80], 12 2026 mattes`。
- 输出重新解析：主图 54 tiles、HDR 15 tiles、style / EXIF / thumbnail / gain map 全保留，
  `texture=true`；`IntegrityVerifier` 11/11 通过。
- 两次转换输出 SHA-256 一致（`90939abf...`）；原图 SHA-256（`7edf1625...`）未变。
- 对输出再次判定为「已有第三代质感」，不会重复处理。

1.2 只增加额度与购买层，没有修改 `StylePortCore` 的纹理 / 颗粒算法或固定转换管线。

## 3. 自动化测试

| Scheme | 结果 | 执行 | 通过 | 跳过 |
| --- | --- | --- | --- | --- |
| `LingXiKitTests` | TEST SUCCEEDED | 26 | 26 | 0 |
| `LingXiPurchaseTests` | TEST SUCCEEDED | 20 | 20 | 0 |
| `LingXiEngineTests` | TEST SUCCEEDED | 2 | 2 | 0 |
| `StylePortCoreTests` | TEST SUCCEEDED | 14 | 12 | 2 |

合计执行 62 项，60 项通过，2 项因缺少外部 fixture 跳过。

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiPurchaseTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
```

### 3.1 LingXiKitTests（26）

- `ISOBoxTests`：ISO BMFF 同级 box 解析、尾部填充容忍。
- `HEIFReferenceTests`：`iref` 子 box 的 16-bit / 32-bit ID 解析；损坏条目只产生 warning。
- `CompatibilityTests`：完整 HEIC 可解锁；已编辑资产提示后仍可转换；Live Photo 拒绝；
  已含第三代质感不重复处理；非 HEIF 只报容器问题。
- `ConversionRunTests`（6）：已保存项不重复转换；取消保留已完成项；未开始即取消；
  旧 session token 不能完成新会话；unsupported / unavailable 不阻塞后续项；旧完成回调被忽略。
- `QuotaTests`（10）：初始满额、成功扣减、释放不扣、提交幂等、自然日重置、耗尽拒绝、两进程抢最后一槽、跨实例读回、Pro 绕过、过期预留回收。
- 其余：`ConversionStage` 顺序与文案、输出命名稳定性。

### 3.2 LingXiPurchaseTests（20）

`StoreKitPurchaseTests`（13）：

1. 本地配置加载非消耗型商品，Product ID 与显示名正确。
2. USA / CHN / JPN / DEU 四个 storefront 的价格来自 StoreKit，货币符号与
   `priceFormatStyle.currencyCode` 一致，且四个价格不全相同（证明未硬编码）。
3. 成功购买后 `PurchaseManager.isPro` 与 `StoreKitEntitlementProvider.isPro()` 同时为真。
4. 用户取消不授予 Pro，不产生交易。
5. 网络失败显示中文错误，不授予 Pro。
6. 交易 pending 时不授予；批准后由交易监听解锁。
7. 恢复购买恢复 Pro。
8. 重启后仍能读取已验签交易。
9. 退款 / 撤销后 Pro 失效，回到免费额度。
10. 重复交易回调不会重复授予。
11. 商品加载失败提供友好错误与重试入口。
12. 共享额度：三个 `ConversionService` 实例使用同一 SQLite 文件，任意入口提交后其余入口
    立即看到已用 1 张，剩余 9 张。
13. **失败转换不扣额度**：损坏 HEIC 在预检阶段失败，记录一次预留与一次释放、零提交，
    额度仍为 10/10。

`KeychainQuotaTests`（7）：

1. reserve / commit / release 只占一个槽。
2. commit 幂等；迟到的 release 不能抹掉已提交额度。
3. 两个独立 store 竞争最后 1 个槽，只有一个成功。
4. 超过 30 分钟的预留会被回收。
5. 本地自然日切换后额度重置。
6. 新建 store 实例仍能读到已提交记录（模拟进程重启）。
7. Pro 完全绕过 Keychain 账本。

`LingXiStoreKitEntitlementProvider` 只接受 `.verified` 交易；未验签、pending、取消、
网络失败都不会写入 Pro 状态。

### 3.3 LingXiEngineTests（2）

- JPEG 输入拒绝，错误码 `E_UNSUPPORTED:notHEIC`。
- 输出名稳定为 `IMG_0001_TextureGrain.heic`，重复处理不叠加后缀。

### 3.4 StylePortCoreTests（14，2 跳过）

上游编码核心的结构测试。跳过的 2 项依赖 `STYLEPORT_FIXTURES` /
`STYLEPORT_LIVE_VIDEO` 环境变量，未配置，不是失败。

## 4. 1.2 实现审查

| 项 | 验证方式 | 结论 |
| --- | --- | --- |
| 免费额度 10 张 / 本地自然日 | `QuotaTests` + `KeychainQuotaTests` + 模拟器 | ✅ 成功转换扣 1 张；跨重启保持 9/10 |
| 失败 / 跳过 / 不兼容不扣 | 新增失败转换测试 + 流程审查 | ✅ 失败只释放预留；跳过项不进入 `ConversionService` |
| 所有入口共享同一账本 | 三个 `ConversionService` 共享 SQLite 的单测；源码审查 | ✅ App / Share / Shortcuts 都调用 `ConversionService`；跨进程运行未实测 |
| 额度持久化、非 UserDefaults 读改写 | Keychain 槽位账本 + SQLite `BEGIN IMMEDIATE` | ✅ 未使用 UserDefaults；Keychain 单槽 `SecItemAdd` 原子占位 |
| Pro 一次性永久无限 | StoreKit 2 非消耗型 + 13 项测试 + 模拟器本地购买 | ✅ 购买 / 恢复 / 退款 / 重复回调均覆盖；模拟器购买后重启仍为 Pro；真实扣款未做 |
| 必须 StoreKit 验证后授予 | `StoreKitEntitlementProvider` 只接受 `.verified` | ✅ 单测覆盖未验签不授予 |
| 交易监听 / 未完成交易 | `Transaction.updates` + `PurchaseManager.start()` | ✅ 代码审查 + pending 测试 |
| 价格只用 `displayPrice` | 四地区价格测试 + 源码检索 | ✅ 无硬编码货币符号或金额；加载失败显示重试 |
| 首页今日剩余 / Pro 无限 | 模拟器截图 + `QuotaBadge` 审查 | ✅ 免费 10/10、9/10 与购买后 Pro 无限均已目视 |
| 独立 Pro 页 | 模拟器截图 | ✅ 本地价格、购买 CTA、恢复购买、法律说明 |
| 额度耗尽页 | 模拟器 + `QuotaExhaustedView` | ✅ 临时上限 1 触发；升级按钮同 sheet 切换 Pro；已还原 10 |
| 批量超额度提示 | `AppModel.startConversion` 审查 | 🟡 计算剩余额度并只处理可转数量；未运行批量超额 |
| 首次启动不弹付费 | `AppModel.onAppear` 审查 + 模拟器首页 | ✅ 仅刷新权限与额度，不主动展示 Pro |
| 深浅色 / Dynamic Type / 无障碍 | 令牌、Preview、1.1 模拟器检查 | ✅ 页面令牌未退回硬编码色；1.2 新增 Pro 页未做最大字号目视 |
| 版本 1.2.0 / build 3 | `project.yml` + 构建产物 | ✅ |
| 本地 StoreKit 配置仅 Debug | scheme 检查 | ✅ Debug LaunchAction 绑定，Release 不绑定 |
| 不依赖 App Group | `QuotaManager` 回退路径 | ✅ 无 App Group 时使用 Keychain；有容器时优先 SQLite |

## 5. 设备测试矩阵

状态：✅ 已验证（自动化 / 引擎层 / 模拟器）；🟡 已实现并通过编译，未运行；⚪ 未执行。
模拟器结果不能替代真机。

| # | 场景 | 预期 | 状态 |
| --- | --- | --- | --- |
| 1 | 12MP HEIC 原片 | 成功，另存新照片，原图不变 | ⚪ |
| 2 | 24MP HEIC 原片 | 成功 | ⚪ |
| 3 | 48MP Pro 原片（多 tile grid） | 成功，逐 tile 无损 | ✅ 模拟器端到端（54 tiles，11/11） |
| 4 | HDR / Gain Map 照片 | 成功，HDR 元数据保留 | ✅ 模拟器端到端（15 个 gain-map tiles） |
| 5 | 夜景 / 人像 | 成功，纹理只追加不替换 | ⚪ |
| 6 | 已含第三代质感 | 「无需转换」，不写入相册 | ✅ 自动化 + 模拟器 |
| 7 | Live Photo | 跳过并提示，不处理视频 | ✅ 自动化 |
| 8 | JPEG | 拒绝，中文原因 | ✅ 引擎层 |
| 9 | PNG / TIFF / DNG | 拒绝 | ⚪ |
| 10 | RAW / RAW+HEIC | 「暂不支持」 | ⚪ |
| 11 | 已编辑 Asset | 提示基于当前原件另存，不覆盖 | ⚪ |
| 12 | iCloud 原件未下载 | 真实下载进度，完成后继续 | 🟡 已接 progressHandler，未真机 |
| 13 | 分享面板返回 JPEG | 扩展拒绝并提示回 App 选图 | 🟡 已实现，未真机 |
| 14 | PhotosPicker 返回 JPEG | 拒绝并提示 | ⚪ |
| 15 | 相册权限「受限」 | 只显示可访问照片，流程可用 | ⚪ |
| 16 | 相册写入权限拒绝 | 中文提示 + `E_PHOTO_ADD_DENIED` | 🟡 已实现，未真机 |
| 17 | 存储空间不足 | 失败并说明原因，不产生半张照片 | ⚪ |
| 18 | 批量转换中取消 | 当前张到安全边界；已保存保留；未开始取消 | 🟡 状态机自动化通过，未真机 |
| 19 | 重试失败项 | 只重转失败项，不重复保存已成功项 | 🟡 ConversionRun 自动化通过，未真机 |
| 20 | 免费额度成功扣减 | 10/10 → 9/10，重启仍 9/10 | ✅ 模拟器端到端 |
| 21 | 失败 / 跳过不扣额度 | 额度不变 | ✅ 自动化（失败转换释放预留） |
| 22 | 额度耗尽页 | 显示永久解锁与明天继续免费 | ✅ 模拟器（临时上限 1 触发，已还原 10） |
| 23 | 批量超过剩余额度 | 提示实际可转数量，只转剩余 | 🟡 已实现，未运行 |
| 24 | 购买成功解锁 Pro | 首页显示 Pro 无限，重启保持 | ✅ StoreKit 自动化 + 模拟器本地购买 + 重启目视 |
| 25 | 取消 / 失败 / pending 购买 | 不授予 Pro；pending 批准后授予 | ✅ StoreKit 自动化 |
| 26 | 恢复购买 | 恢复 Pro | ✅ StoreKit 自动化 |
| 27 | 退款 / 撤销 | Pro 失效，回到免费额度 | ✅ StoreKit 自动化 |
| 28 | 商品加载失败 | 友好错误 + 重试，不显示虚构价格 | ✅ StoreKit 自动化 |
| 29 | 四地区价格 | USA / CHN / JPN / DEU 由 StoreKit 本地化 | ✅ StoreKit 自动化，本地配置 |
| 30 | 真实扣款 / App Store Sandbox | 真实交易可恢复、可退款 | ⚪ 未连接 App Store |
| 31 | 分享扩展额度共享 | 扩展转换后 App 额度减少 | 🟡 代码共用 `ConversionService`；未真机 |
| 32 | 快捷指令额度共享 | 三个参数都受额度约束 | 🟡 代码共用 `ConversionService`；未真机 |
| 33 | 深色 / 浅色 | 真动态色，对比度 ≥ 4.5:1 | ✅ 1.1 模拟器目视；1.2 Pro 页未深色目视 |
| 34 | Dynamic Type 大字号 | 布局不截断，主按钮仍可点 | ✅ 1.1 模拟器 accessibility-large；1.2 新增页未验 |
| 35 | Reduce Motion | 关闭扫光 / 呼吸光 / 缩放 | 🟡 代码审查，未运行 |
| 36 | VoiceOver | 大图、缩略图、进度、错误、额度可读 | ⚪ 未运行 |
| 37 | 快捷指令（保存 / 返回文件 / 仅检查） | 统计正确，文件可回传 | 🟡 已实现，未真机 |
| 38 | 分享扩展完整闭环 | 保存新照片，失败有中文提示 | 🟡 已实现，未真机 |
| 39 | 7 天签名过期 | 重新安装后可继续使用，照片不丢 | ⚪ |

## 6. 已知风险与未验证项

1. **没有真实 App Store 交易。** 自动化断言来自 `SKTestSession`，模拟器手动购买也使用
   本地 `Configuration.storekit`；Xcode 明确提示不会扣款。真实 App Store 商品、税务 /
   银行信息、Sandbox 账号、退款到账时延都未验证。上线前必须按 `AppStoreRelease.md`
   在 Sandbox 走一遍。
2. **没有 1.2 真机安装。** 分享扩展与快捷指令是否与主 App 共用 Keychain 额度，取决于
   真机 entitlements 与 `LingXiKeychainGroup` 是否正确展开；模拟器空 entitlements 的通过
   不能证明真机跨进程共享。
3. **App Group 路径未启用。** 免费 Personal Team 没有 App Group entitlement，当前真机
   默认走 Keychain；若使用付费团队并开启 App Group，SQLite 路径的跨进程事务需要在真机复测。
4. **批量超额提示只做了代码审查。** 额度耗尽页与「耗尽 → Pro」切换已用临时上限 1 在
   模拟器走通（之后已还原为 10）；批量选择超过剩余额度时的提示与「仅转换 N 张」仍未运行。
5. **Pro 页只做了浅色与标准字号目视。** 深色、最大 Dynamic Type、VoiceOver 下按钮与
   法律说明的可达性未逐项检查。
6. **系统矩阵仍空白。** 12MP / 24MP、夜景、人像、RAW、iCloud 下载、权限受限、存储不足、
   取消 / 重试、分享扩展、快捷指令均未在 1.2 真机验收。
7. `StylePortCoreTests` 有 2 项跳过，因为未设置 `STYLEPORT_FIXTURES` /
   `STYLEPORT_LIVE_VIDEO`，不是代码失败。
8. 免费 Personal Team 签名 7 天过期，属预期限制。
9. Keychain 账本用 10 个固定槽位表达每日额度；这是为跨进程原子性做的取舍，不做通用数据库。
   卸载重装不保证重置：Keychain 条目可能由系统保留，本版本也不会主动清除服务
   `com.lingxifox.LingXiStyle.quota`。
10. 本地 StoreKit 配置已移除开发者 Team ID，测试仍通过；配置中的 `$4.99` 仅用于测试。

## 7. 建议的验收顺序

1. 用付费团队或 Personal Team 在真机安装 1.2，确认首页显示 10/10，且首次启动不弹付费页。
2. 转换 1 张，确认扣到 9/10；杀掉 App 重开，确认仍为 9/10。
3. 用损坏 HEIC、JPEG、Live Photo、已含质感照片各试一次，确认全部不扣额度。
4. 连续转换到第 11 张，确认额度耗尽页；用 3 张批量但只剩 1 张额度，确认只转 1 张。
5. 在 Sandbox 购买 Pro，确认首页切换为无限、重启保持；再测恢复购买与退款。
6. 用分享扩展和快捷指令各转换 1 张，回到主 App 确认额度同步减少（真机跨进程关键项）。
7. 在深色、最大 Dynamic Type、Reduce Motion、VoiceOver 下走首页、Pro 页、额度耗尽页。
8. 最后补 12MP / 24MP、iCloud、权限拒绝、存储不足、取消 / 重试与横竖屏矩阵。
