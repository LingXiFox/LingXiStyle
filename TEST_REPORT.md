# TEST_REPORT

- 日期：2026-11-07
- 项目：LingXiStyle 1.3.0（build 4），公开名称：简体中文「纹粒」，繁体中文 / 英文 / 日文「Texel」
- 结论：**XcodeGen 生成、Debug / Release 构建与全部自动化测试通过。1.3 在 iPhone 17（402 × 874 pt）模拟器完成四语言首页、深色与 Pro 页面目视验收，在 iPhone Duo（466 × 678 pt 折叠屏）完成 5 / 5 免费态与紧凑布局验收；紧凑布局无需滚动即可看到全部主操作与隐私文案。真实 App Store 交易、真机、分享扩展与快捷指令的跨进程额度共享仍需验收。**

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.3（26C5035r），Apple Silicon |
| Xcode | 27.3（27C5020n），MacOSX27.3.sdk |
| Swift | Swift 5 语言模式（`SWIFT_VERSION=5.0`） |
| 部署目标 | iOS 18.0 |
| 工程生成 | XcodeGen 2.46.0 |
| 签名 | 自动签名；本轮 QA 使用开发者本机 Apple Development Team，仓库不包含 Team ID |
| 模拟器 | iPhone 17，iOS 27.3；iPhone Duo，iOS 27.3（内屏 466 × 678 pt） |
| 真机 | 1.0 曾在 iPhone 16 Pro Max 安装运行；1.3 未做真机安装 |
| StoreKit | 本地 `Configuration.storekit`；没有连接 App Store，没有真实扣款 |

## 2. 构建结果

### 2.1 工程生成与版本

`xcodegen generate` 成功。App 与 ShareExtension 的 Info.plist 均使用
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`，本轮版本为
**1.3.0 / build 4**。

`project.yml` 的 `developmentLanguage` 为 `zh-Hans`，`knownRegions` 为
`zh-Hans, zh-Hant, en, ja`。String Catalog 共：

- `Resources/Localization/Localizable.xcstrings`：328 个 key，覆盖 App、分享扩展与快捷指令文案。
- `Resources/Localization/AppShortcuts.xcstrings`：1 个 App Shortcut 标题。
- `Resources/Localization/InfoPlist.xcstrings`：4 个 key，覆盖应用名与两条相册权限说明。

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

结果：**Debug BUILD SUCCEEDED；Release BUILD SUCCEEDED**，0 error、0 Swift 源码 warning。
日志中只有 `appintentsmetadataprocessor` 的“Metadata extraction skipped”提示与
`StoreKitTest.framework` 头文件里 `SKPaymentTransactionState` 的 SDK 弃用警告，均不影响
App 的 `Metadata.appintents` 或购买结果。

产物包含 `LingXiStyle.app`、`PlugIns/LingXiStyleShare.appex`、嵌入的
`LingXiKit.framework` / `LingXiEngine.framework` / `LingXiServices.framework` /
`StylePortCore.framework`，以及 `Metadata.appintents`。

### 2.3 签名模拟器构建

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/LX13Duo \
  DEVELOPMENT_TEAM=<your team> -allowProvisioningUpdates build
```

结果 **BUILD SUCCEEDED**，同一份模拟器 App 安装并在 iPhone 17 与 iPhone Duo 启动。

> 该 QA 构建由 Xcode 自动签名，entitlements 为空，Keychain 额度仍可读写。
> 不要对 QA 产物手工执行 `codesign --deep`：手工重签会破坏 Keychain 访问。

### 2.4 1.3 模拟器目视验收

| 检查项 | 结果 |
| --- | --- |
| iPhone 17 标准布局（402 × 874 pt） | 品牌「纹粒」；标题、构图框、两个入口、5 / 5 额度与隐私文案全部可见；隐私行位于 y≈819，无需滚动 |
| iPhone 17 英文 | 品牌「Texel」；“Texel Pro · Unlimited”；隐私行位于 y≈841；无截断 |
| iPhone 17 深色 | 深色背景、表面、文本与强调色正常，未见对比度丢失 |
| iPhone Duo 紧凑布局（466 × 678 pt） | `isCompact` 分支生效；品牌 y16、标题 y41–124、主按钮 y420–472、次按钮 y484–532、额度 y544–574、隐私 y586–602，一屏内全部可见 |
| 免费态首页 | Duo 显示「今日剩余 5 / 5 张」，首次启动不弹付费页 |
| Pro 页面 | 从额度徽标打开；本地配置显示 `$2.99`、权益列表、恢复购买与法律说明；购买 CTA 在首屏可见，法律说明在下方滚动 |
| Pro 已购态 | 显示「已解锁 纹粒 Pro」/ “Unlocked Texel Pro” 与本地化说明；英文详情不再回退中文 |
| Pro 页英文 | “No 5-per-day free limit”“Convert 5 photos free every day without buying”“Unlimited conversions are active…” 全部为英文 |
| 品牌与 locales | zh-Hans 显示「纹粒」/「纹粒 Pro」；zh-Hant、en、ja 显示「Texel」/「Texel Pro」；英文 catalog 无中日韩字符残留 |
| 空状态构图框 | 已移除 `ORIGINAL HEIC` 与 `4:5` 两个角落文字；只保留 `HEIC 原片` / `仅补质感` 两枚状态标签 |
| 48MP 转换 | iPhone 17 选择 8064 × 6048 HEIC 显示「可解锁」；转换完成并显示「已保存新照片」；1.3 引擎未改算法，完整性基线沿用 1.2 的 11 / 11 |
| 大字号 | 1.1 已在 accessibility-large 验证可滚动、主操作可点；1.3 新增文案均来自 String Catalog，未引入固定高度文本 |

本地 StoreKit 配置的 `$2.99` 只用于自动化与模拟器，**不是线上价格**；线上价格必须来自
App Store Connect 的 `Product.displayPrice`。

### 2.5 真实 HEIC 引擎基线（1.0 / 1.2 验证，1.3 未改算法）

- 输入 8064 × 6048 HEIC，125 items、54 主图 tiles、15 HDR tiles。
- `ConversionEngine.convert` 返回 `mode=add-texture`；输出 5,933,004 字节，
  `texture=added #151 -> [55, 80], 12 2026 mattes`。
- 输出重新解析：主图 54 tiles、HDR 15 tiles、style / EXIF / thumbnail / gain map 全保留，
  `texture=true`；`IntegrityVerifier` 11 / 11 通过。
- 两次转换输出 SHA-256 一致（`90939abf...`）；原图 SHA-256（`7edf1625...`）未变。
- 对输出再次判定为「已有第三代质感」，不会重复处理。

1.3 只改品牌、本地化、额度上限与响应式布局，没有修改 `StylePortCore` 的纹理 / 颗粒算法
或固定转换管线。

## 3. 自动化测试

| Scheme | 结果 | 执行 | 通过 | 跳过 |
| --- | --- | --- | --- | --- |
| `LingXiKitTests` | TEST SUCCEEDED | 27 | 27 | 0 |
| `LingXiPurchaseTests` | TEST SUCCEEDED | 21 | 21 | 0 |
| `LingXiEngineTests` | TEST SUCCEEDED | 2 | 2 | 0 |
| `StylePortCoreTests` | TEST SUCCEEDED | 14 | 12 | 2 |

合计执行 64 项，62 项通过，2 项因缺少外部 fixture 跳过。

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

### 3.1 LingXiKitTests（27）

- `ISOBoxTests`（2）：ISO BMFF 同级 box 解析、尾部填充容忍。
- `HEIFReferenceTests`（3）：`iref` 子 box 的 16-bit / 32-bit ID 解析；损坏条目只产生 warning。
- `CompatibilityTests`（5）：完整 HEIC 可解锁；已编辑资产提示后仍可转换；Live Photo 拒绝；
  已含第三代质感不重复处理；非 HEIF 只报容器问题。
- `ConversionRunTests`（6）：已保存项不重复转换；取消保留已完成项；未开始即取消；
  旧 session token 不能完成新会话；unsupported / unavailable 不阻塞后续项；旧完成回调被忽略。
- `QuotaTests`（11）：初始 5 / 5；成功扣减；释放不扣；提交幂等；第 5 张耗尽、第 6 张拒绝；
  自然日重置；耗尽拒绝；两进程抢最后一槽；跨实例读回；Pro 绕过；过期预留回收。

### 3.2 LingXiPurchaseTests（21）

`StoreKitPurchaseTests`（13）：

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
12. 共享额度：三个 `ConversionService` 实例使用同一账本，任意入口提交后其余入口
    立即看到已用 1 张。
13. **失败转换不扣额度**：损坏 HEIC 在预检阶段失败，记录一次预留与一次释放、零提交，
    额度仍为 5 / 5。

`KeychainQuotaTests`（8）：

1. 默认额度为 5 张。
2. reserve / commit / release 只占一个槽。
3. commit 幂等；迟到的 release 不能抹掉已提交额度。
4. 两个独立 store 竞争最后 1 个槽，只有一个成功。
5. 超过 30 分钟的预留会被回收。
6. 本地自然日切换后额度重置。
7. 新建 store 实例仍能读到已提交记录（模拟进程重启）。
8. Pro 完全绕过 Keychain 账本。

`LingXiStoreKitEntitlementProvider` 只接受 `.verified` 交易；未验签、pending、取消、
网络失败都不会写入 Pro 状态。

### 3.3 LingXiEngineTests（2）

- JPEG 输入拒绝，错误码 `E_UNSUPPORTED:notHEIC`。
- 输出名稳定为 `IMG_0001_TextureGrain.heic`，重复处理不叠加后缀。

### 3.4 StylePortCoreTests（14，2 跳过）

上游编码核心的结构测试。跳过的 2 项依赖 `STYLEPORT_FIXTURES` /
`STYLEPORT_LIVE_VIDEO` 环境变量，未配置，不是失败。

## 4. 1.3 实现审查

| 项 | 验证方式 | 结论 |
| --- | --- | --- |
| 品牌更名 | `Brand.name` / `Brand.proName` + 四语言模拟器 | ✅ zh-Hans「纹粒」；zh-Hant / en / ja「Texel」 |
| 内部标识稳定 | 源码审查 | ✅ Bundle ID、StoreKit Product ID、Keychain 服务名仍为 LingXiStyle，升级与购买不中断 |
| 四语言 catalog | 328 + 1 + 4 key；各语言截图 | ✅ App、分享扩展、快捷指令、Info.plist 全覆盖；英文无 CJK 残留 |
| 5 张 / 日额度 | `QuotaTests`（11）+ `KeychainQuotaTests`（8）+ Duo 首页 | ✅ 上限 5；免费态显示 5 / 5 |
| 额度文案随上限插值 | `ProPurchaseView` 使用 `QuotaConfiguration.freeDailyLimit` | ✅ 不再写死 10，避免改上限后文案漂移 |
| 所有入口共享额度 | 三个 `ConversionService` 单测 + 源码审查 | ✅ App / 分享扩展 / 快捷指令都走同一服务；真机跨进程未实测 |
| Pro 一次性永久无限 | StoreKit 2 非消耗型 + 13 项测试 | ✅ 购买 / 恢复 / 退款 / 重复回调均覆盖；真实扣款未做 |
| 价格只用 `displayPrice` | 四地区价格测试 + 源码检索 | ✅ 无硬编码金额；`$2.99` 仅来自本地测试配置 |
| 首页额度 / Pro 徽标 | 模拟器截图 + `QuotaBadge` 审查 | ✅ 免费 5 / 5；Pro 「无限转换」；Pro 用户仍可打开 Pro 页恢复购买 |
| 独立 Pro 页 | 模拟器截图（zh-Hans / en） | ✅ 本地价格、权益、购买态、恢复购买、法律说明 |
| 额度耗尽页 | 1.2 临时上限 1 触发；1.3 代码未改结构 | ✅ 升级与「明天继续」两个出口；已还原正式上限 |
| 响应式布局 | iPhone 17 与 Duo 截图 | ✅ 标准高度走 260pt 构图框；< 760pt 走 152pt 紧凑构图框 |
| 批量超额度提示 | `AppModel.startConversion` 审查 | 🟡 计算剩余额度并只处理可转数量；未运行批量超额 |
| 首次启动不弹付费 | `AppModel.onAppear` 审查 + 模拟器首页 | ✅ 仅刷新权限与额度 |
| 深浅色 / Dynamic Type / 无障碍 | 令牌、Preview、iPhone 17 深色与 1.1 大字号检查 | ✅ 品牌页与 Pro 页令牌未退回硬编码色；1.3 未重跑 VoiceOver |
| 版本 1.3.0 / build 4 | `project.yml` + 构建产物 | ✅ |
| 本地 StoreKit 配置仅 Debug | scheme 检查 | ✅ Debug LaunchAction 绑定，Release 不绑定 |
| 不依赖 App Group | `QuotaManager` 回退路径 | ✅ 无 App Group 时使用 Keychain |

## 5. 设备测试矩阵

状态：✅ 已验证（自动化 / 引擎层 / 模拟器）；🟡 已实现并通过编译，未运行；⚪ 未执行。
模拟器结果不能替代真机。

| # | 场景 | 预期 | 状态 |
| --- | --- | --- | --- |
| 1 | 12MP HEIC 原片 | 成功，另存新照片，原图不变 | ⚪ |
| 2 | 24MP HEIC 原片 | 成功 | ⚪ |
| 3 | 48MP Pro 原片（多 tile grid） | 成功，逐 tile 无损 | ✅ 1.2 引擎 54 tiles / 11 / 11；1.3 模拟器成功保存 |
| 4 | HDR / Gain Map 照片 | 成功，HDR 元数据保留 | ✅ 1.2 引擎 15 个 gain-map tiles；1.3 未改算法 |
| 5 | 夜景 / 人像 | 成功，纹理只追加不替换 | ⚪ |
| 6 | 已含第三代质感 | 「无需转换」，不写入相册 | ✅ 自动化 + 模拟器 |
| 7 | Live Photo | 跳过并提示，不处理视频 | ✅ 自动化 |
| 8 | JPEG | 拒绝，本地化原因 | ✅ 引擎层 |
| 9 | PNG / TIFF / DNG | 拒绝 | ⚪ |
| 10 | RAW / RAW+HEIC | 「暂不支持」 | ⚪ |
| 11 | 已编辑 Asset | 提示基于当前原件另存，不覆盖 | ⚪ |
| 12 | iCloud 原件未下载 | 真实下载进度，完成后继续 | 🟡 已接 progressHandler，未真机 |
| 13 | 分享面板返回 JPEG | 扩展拒绝并提示回 App 选图 | 🟡 已实现，未真机 |
| 14 | PhotosPicker 返回 JPEG | 拒绝并提示 | ⚪ |
| 15 | 相册权限「受限」 | 只显示可访问照片，流程可用 | ⚪ |
| 16 | 相册写入权限拒绝 | 提示 + `E_PHOTO_ADD_DENIED` | 🟡 已实现，未真机 |
| 17 | 存储空间不足 | 失败并说明原因，不产生半张照片 | ⚪ |
| 18 | 批量转换中取消 | 当前张到安全边界；已保存保留；未开始取消 | 🟡 状态机自动化通过，未真机 |
| 19 | 重试失败项 | 只重转失败项，不重复保存已成功项 | 🟡 ConversionRun 自动化通过，未真机 |
| 20 | 免费额度成功扣减 | 5 / 5 起，成功一次扣 1；重启仍保留 | ✅ 自动化；1.3 UI 已验证免费态 5 / 5 |
| 21 | 失败 / 跳过不扣额度 | 额度不变 | ✅ 自动化（失败转换释放预留） |
| 22 | 额度耗尽页 | 显示永久解锁与明天继续免费 | ✅ 1.2 模拟器（临时上限触发，已还原） |
| 23 | 批量超过剩余额度 | 提示实际可转数量，只转剩余 | 🟡 已实现，未运行 |
| 24 | 购买成功解锁 Pro | 首页显示 Pro 无限，重启保持 | ✅ StoreKit 自动化；1.2 本地购买 + 重启目视 |
| 25 | 取消 / 失败 / pending 购买 | 不授予 Pro；pending 批准后授予 | ✅ StoreKit 自动化 |
| 26 | 恢复购买 | 恢复 Pro | ✅ StoreKit 自动化 |
| 27 | 退款 / 撤销 | Pro 失效，回到免费额度 | ✅ StoreKit 自动化 |
| 28 | 商品加载失败 | 友好错误 + 重试，不显示虚构价格 | ✅ StoreKit 自动化 |
| 29 | 四地区价格 | USA / CHN / JPN / DEU 由 StoreKit 本地化 | ✅ StoreKit 自动化，本地配置 `$2.99` |
| 30 | 真实扣款 / App Store Sandbox | 真实交易可恢复、可退款 | ⚪ 未连接 App Store |
| 31 | 分享扩展额度共享 | 扩展转换后 App 额度减少 | 🟡 代码共用 `ConversionService`；未真机 |
| 32 | 快捷指令额度共享 | 三个参数都受额度约束 | 🟡 代码共用 `ConversionService`；未真机 |
| 33 | 深色 / 浅色 | 真动态色，对比度 ≥ 4.5:1 | ✅ 1.1 + 1.3 iPhone 17 首页深色目视；Pro 页深色未逐项 |
| 34 | Dynamic Type 大字号 | 布局不截断，主按钮仍可点 | ✅ 1.1 accessibility-large；1.3 未重跑 |
| 35 | Reduce Motion | 关闭扫光 / 呼吸光 / 缩放 | 🟡 代码审查，未运行 |
| 36 | VoiceOver | 大图、缩略图、进度、错误、额度可读 | ⚪ 未运行 |
| 37 | 快捷指令（保存 / 返回文件 / 仅检查） | 统计正确，文件可回传 | 🟡 已实现，未真机 |
| 38 | 分享扩展完整闭环 | 保存新照片，失败有本地化提示 | 🟡 已实现，未真机 |
| 39 | 7 天签名过期 | 重新安装后可继续使用，照片不丢 | ⚪ |
| 40 | 折叠 / 紧凑屏幕 | 全部主操作与隐私文案一屏可见 | ✅ iPhone Duo 466 × 678 pt 模拟器 |

## 6. 已知风险与未验证项

1. **没有真实 App Store 交易。** 自动化断言来自 `SKTestSession`，模拟器购买使用本地
   `Configuration.storekit`；真实商品、税务 / 银行信息、Sandbox 账号、退款到账时延都未验证。
   上线前必须按 `AppStoreRelease.md` 在 Sandbox 走一遍。
2. **没有 1.3 真机安装。** 分享扩展与快捷指令是否与主 App 共用 Keychain 额度，取决于
   真机 entitlements 与 `LingXiKeychainGroup` 是否正确展开；模拟器空 entitlements 的通过
   不能证明真机跨进程共享。
3. **App Group 路径未启用。** 免费 Personal Team 没有 App Group entitlement，当前真机
   默认走 Keychain；若使用付费团队并开启 App Group，SQLite 路径的跨进程事务需要在真机复测。
4. **批量超额提示只做了代码审查。** 额度耗尽页与「耗尽 → Pro」切换在 1.2 用临时上限走通；
   1.3 批量选择超过 5 张时的提示与「仅转换 N 张」仍未运行。
5. **Pro 页只做了浅色标准字号与英文目视。** 深色、最大 Dynamic Type、VoiceOver 下按钮与
   法律说明的可达性未逐项检查。
6. **系统矩阵仍空白。** 12MP / 24MP、夜景、人像、RAW、iCloud 下载、权限受限、存储不足、
   取消 / 重试、分享扩展、快捷指令均未在 1.3 真机验收。
7. **Duo 只验证了首页。** 折叠屏上的选片、转换、结果页没有跑通；模拟器 PhotosPicker 在
   Duo 上出现输入无响应，不能据此判定 App 逻辑，也不能写成通过。
8. `StylePortCoreTests` 有 2 项跳过，因为未设置 `STYLEPORT_FIXTURES` /
   `STYLEPORT_LIVE_VIDEO`，不是代码失败。
9. 免费 Personal Team 签名 7 天过期，属预期限制。
10. Keychain 账本用固定槽位表达每日额度；这是为跨进程原子性做的取舍，不做通用数据库。
    卸载重装不保证重置：Keychain 条目可能由系统保留，本版本也不会主动清除服务
    `com.lingxifox.LingXiStyle.quota`。
11. 本地 StoreKit 配置的 `$2.99` 仅用于测试；配置仍保留德文商品本地化，但 App UI 当前
    只提供 zh-Hans / zh-Hant / en / ja 四种语言。

## 7. 建议的验收顺序

1. 用付费团队或 Personal Team 在真机安装 1.3，确认首页显示 5 / 5，且首次启动不弹付费页。
2. 转换 1 张，确认扣到 4 / 5；杀掉 App 重开，确认仍为 4 / 5。
3. 用损坏 HEIC、JPEG、Live Photo、已含质感照片各试一次，确认全部不扣额度。
4. 连续转换到第 6 张，确认额度耗尽页；用 3 张批量但只剩 1 张额度，确认只转 1 张。
5. 在 Sandbox 购买 Pro，确认首页切换为无限、重启保持；再测恢复购买与退款。
6. 用分享扩展和快捷指令各转换 1 张，回到主 App 确认额度同步减少（真机跨进程关键项）。
7. 在深色、最大 Dynamic Type、Reduce Motion、VoiceOver 下走首页、Pro 页、额度耗尽页。
8. 最后补 12MP / 24MP、iCloud、权限拒绝、存储不足、取消 / 重试与横竖屏矩阵。
