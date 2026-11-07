# TEST_REPORT

- 日期：2026-11-07
- 项目：LingXiStyle 1.6.0（build 7），公开名称：简体中文「纹粒」，繁体中文 / 英文 / 日文「Texel」
- 结论：**XcodeGen 生成、Debug / Release 构建与全部自动化测试通过。1.6 完成发布质量收口：跨入口额度竞态改为延后而不是失败，快捷指令补齐取消 / 重名 / 超额度处理，分享扩展补齐 fileURL 输入、陈旧临时目录清理与额度耗尽提示，Keychain 无共享组权限时 fail-closed。模拟器复验了 48MP 转换、5 / 5 → 4 / 5 额度、批量「仅转换剩余额度」、英文额度页、深色首页 / Pro 页与 iPhone Duo 紧凑首页；分享扩展在模拟器停在读取阶段，未完成端到端，真实 App Store 交易、真机、快捷指令与完整设备矩阵仍未验收。**

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.3（26C5035r），Apple Silicon |
| Xcode | 27.3（27C5020n），MacOSX27.3.sdk |
| Swift | Swift 5 语言模式（`SWIFT_VERSION=5.0`） |
| 部署目标 | iOS 18.0 |
| 工程生成 | XcodeGen 2.46.0 |
| 签名 | 自动签名；本轮 QA 使用开发者本机 Apple Development Team，仓库不包含 Team ID |
| 模拟器 | iPhone 17，iOS 27.3（402 × 874 pt）；iPhone Duo，iOS 27.3（内屏 466 × 678 pt） |
| 真机 | 1.0 曾在 iPhone 16 Pro Max 安装运行；1.6 未做真机安装 |
| StoreKit | 本地 `Configuration.storekit`；没有连接 App Store，没有真实扣款 |

## 2. 构建结果

### 2.1 工程生成与版本

`xcodegen generate` 成功。App 与 ShareExtension 的 Info.plist 均使用
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`，本轮版本为
**1.6.0 / build 7**。

`project.yml` 的 `developmentLanguage` 为 `zh-Hans`，`knownRegions` 为
`zh-Hans, zh-Hant, en, ja`。String Catalog 共：

- `Resources/Localization/Localizable.xcstrings`：423 个 key，覆盖 App、分享扩展与快捷指令文案。
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
日志中只剩 `appintentsmetadataprocessor` 的“Metadata extraction skipped”提示，不影响
App 的 `Metadata.appintents`。

产物包含 `LingXiStyle.app`、`PlugIns/LingXiStyleShare.appex`、嵌入的
`LingXiKit.framework` / `LingXiEngine.framework` / `LingXiServices.framework` /
`StylePortCore.framework`，以及 `Metadata.appintents`。

### 2.3 签名模拟器构建

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'platform=iOS Simulator,id=<iPhone 17 UDID>' \
  -derivedDataPath /tmp/LX16Sim \
  DEVELOPMENT_TEAM=<your team> -allowProvisioningUpdates build
```

结果 **BUILD SUCCEEDED**，产物安装并在 iPhone 17 与 iPhone Duo 启动。

> 该 QA 构建由 Xcode 自动签名，entitlements 为空，Keychain 额度仍可读写。
> 不要对 QA 产物手工执行 `codesign --deep`：手工重签会破坏 Keychain 访问。

### 2.4 1.6 模拟器目视验收

| 检查项 | 结果 |
| --- | --- |
| 干净安装与额度 | `simctl keychain reset` 后重装，首页显示「今日剩余 5 / 5 张」；首次启动不弹付费页 |
| 48MP 转换 | 选 8064 × 6048 HEIC，显示 `8,064 × 6,048 · 48MP`、HDR、含风格信息；转换约 1 秒；结果「已存入相册 / 成功 1 张 / 跳过 0 / 失败 0」；输出 `IMG_5296_TextureGrain.HEIC` |
| 成功扣额度 | 转换后首页显示 4 / 5；杀掉 App 重开仍为 4 / 5 |
| 英文切换 | 设置切到 English 后重启；首页为 Texel、「Today: 4 / 5 free」，无中文残留 |
| 批量额度提示 | 9 选 6 张可处理、3 张跳过，剩 4 张额度；提示「你选择了 6 张可处理照片，今日还剩 4 张免费额度…」；选「仅处理 4 张」后结果成功 4、跳过 3、失败 0、还有 2 张未处理 |
| 批量后额度 | 4 张成功后额度到 0，Pro 页自动出现一次；关闭后首页「今日免费额度已用完」 |
| 英文额度页 | 0 / 5 时再次选择，自动打开英文额度页：Resets at local midnight; 5 free photos return tomorrow. Photos that weren’t processed don’t use quota. |
| 深色模式 | 深色首页与 Pro 页正常；狐橙按钮、表面与文本对比度可读；恢复浅色 |
| iPhone Duo | 466 × 678 pt 紧凑首页一屏显示品牌、标题、副标题、三行分组、两个入口、额度与 footnote，5 / 5 无裁切；仅验证首页 |
| 设置页 | 原生 Form；Pro 行副标题「一次购买，永久不限张数。」；语言行原生高度；语言与 About footer 正确 |
| 分享扩展 | 从「照片」分享 48MP 原片，扩展显示「正在读取分享的照片」，超过 7 秒未进入检查；取消后显示「已取消 / 没有读取或保存任何照片。」；额度仍为 5 / 5，无崩溃日志。**未完成端到端** |

1.6 发现并修复的可见问题：

- 英文批量结果页曾出现硬编码中文「今日免费额度不足…」；`App/Sources/Views/ResultView.swift:332` 改为
  `String(localized: "result.deferredQuota", defaultValue: ...)`，并在 423-key catalog 中补四语言。
  编译产物中 en / zh-Hant 值已确认；因额度已到 0，未再次目视英文批量结果页。
- 中文批量旧文案出现在英文结果页的问题属于 1.6 发布阻断项，已修复；不得把“编译通过”写成“已目视”。
- 批量跨入口竞态的真实 UI 未复现：重置额度后，9 张选择最多只有 5 张可处理，无法构造“预检通过、转换时被另一入口抢走最后额度”的现场；该路径由 `ConversionRunTests` 与 Keychain 最后槽位测试覆盖。

本地 StoreKit 配置的 `$2.99` 只用于自动化与 Xcode 启动；**不是线上价格**。通过
`simctl launch` 启动时不会附加 `Configuration.storekit`，Pro 页会如实显示商品不可用与
「重新加载」，不显示虚构价格。

### 2.5 真实 HEIC 引擎基线（1.0 / 1.2 验证，1.6 未改算法）

- 输入 8064 × 6048 HEIC，125 items、54 主图 tiles、15 HDR tiles。
- `ConversionEngine.convert` 返回 `mode=add-texture`；输出 5,933,004 字节，
  `texture=added #151 -> [55, 80], 12 2026 mattes`。
- 输出重新解析：主图 54 tiles、HDR 15 tiles、style / EXIF / thumbnail / gain map 全保留，
  `texture=true`；`IntegrityVerifier` 11 / 11 通过。
- 两次转换输出 SHA-256 一致（`90939abf...`）；原图 SHA-256（`7edf1625...`）未变。
- 对输出再次判定为「无需处理」，不会重复处理。

1.6 只改配额竞态、入口适配、错误文案与测试，没有修改 `StylePortCore` 的纹理 / 颗粒算法
或固定转换管线；引擎基线沿用 1.2。

## 3. 自动化测试

| Scheme | 结果 | 执行 | 通过 | 跳过 |
| --- | --- | --- | --- | --- |
| `LingXiKitTests` | TEST SUCCEEDED | 28 | 28 | 0 |
| `LingXiPurchaseTests` | TEST SUCCEEDED | 22 | 22 | 0 |
| `LingXiEngineTests` | TEST SUCCEEDED | 2 | 2 | 0 |
| `StylePortCoreTests` | TEST SUCCEEDED | 14 | 12 | 2 |

合计执行 66 项，64 项通过，2 项因缺少外部 fixture 跳过。

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

### 3.1 LingXiKitTests（28）

- `ISOBoxTests`（2）：ISO BMFF 同级 box 解析、尾部填充容忍。
- `HEIFReferenceTests`（3）：`iref` 子 box 的 16-bit / 32-bit ID 解析；损坏条目只产生 warning。
- `CompatibilityTests`（5）：完整 HEIC 可添加；已编辑资产提示后仍可转换；Live Photo 拒绝；
  已含纹理与颗粒不重复处理；非 HEIF 只报容器问题。
- `ConversionRunTests`（7）：已保存项不重复转换；取消保留已完成项；未开始即取消；
  旧 session token 不能完成新会话；unsupported / unavailable 不阻塞后续项；旧完成回调被忽略；
  **1.6 新增 `testDeferRemainingLeavesCompletedItemsAlone`：跨入口抢最后额度时，已保存项不变，
  其余 pending 项统一变 deferred，不再记失败。**
- `QuotaTests`（11）：初始 5 / 5；成功扣减；释放不扣；提交幂等；第 5 张耗尽、第 6 张拒绝；
  自然日重置；耗尽拒绝；两进程抢最后一槽；跨实例读回；Pro 绕过；过期预留回收。

### 3.2 LingXiPurchaseTests（22）

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
13. 失败转换不扣额度：损坏 HEIC 在预检阶段失败，记录一次预留与一次释放、零提交，
    额度仍为 5 / 5。

`KeychainQuotaTests`（9）：

1. 默认额度为 5 张。
2. reserve / commit / release 只占一个槽。
3. commit 幂等；迟到的 release 不能抹掉已提交额度。
4. 两个独立 store 竞争最后 1 个槽，只有一个成功。
5. 超过 30 分钟的预留会被回收。
6. 本地自然日切换后额度重置。
7. 新建 store 实例仍能读到已提交记录（模拟进程重启）。
8. Pro 完全绕过 Keychain 账本。
9. **1.6 新增 fail-closed**：配置了共享 access group 但进程没有对应 entitlement 时，
   `status(isPro:)` 抛 `QuotaError.database`，不会静默回退到另一套 Keychain 条目。

`LingXiStoreKitEntitlementProvider` 只接受 `.verified` 交易；未验签、pending、取消、
网络失败都不会写入 Pro 状态。

### 3.3 LingXiEngineTests（2）

- JPEG 输入拒绝，错误码 `E_UNSUPPORTED:notHEIC`。
- 输出名稳定为 `IMG_0001_TextureGrain.heic`，重复处理不叠加后缀。

### 3.4 StylePortCoreTests（14，2 跳过）

上游编码核心的结构测试。跳过的 2 项依赖 `STYLEPORT_FIXTURES` /
`STYLEPORT_LIVE_VIDEO` 环境变量，未配置，不是失败。

## 4. 1.6 实现审查

| 项 | 验证方式 | 结论 |
| --- | --- | --- |
| 跨入口额度竞态 | `AppModel` 源码 + `ConversionRunTests` | ✅ 预检被另一入口抢走最后额度时，当前项与剩余 pending 项转 deferred，结果页不把未处理写成失败；若一张都没保存，回到选择页而不是空结果页 |
| 快捷指令取消 | Intent 源码 | ✅ 每个输入前 `Task.checkCancellation()`；取消不再继续转换后续照片 |
| 快捷指令重名输入 | Intent 源码 | ✅ 每张照片独立 `item-\(index)` 目录；同名文件不会互相覆盖 |
| 快捷指令额度耗尽 | Intent 源码 | ✅ 捕获 `QuotaError.exhausted` 后停止，统计未处理数量，不继续消耗后续预检 |
| 快捷指令安全文件名 | `safeName` 源码 | ✅ 去控制字符、去路径、拒绝 `.` / `..`、限制 160 字符 |
| 分享扩展 fileURL 输入 | 源码审查 | ✅ `public.fileURL` 可作为无图片类型时的回退；仍然做字节级 HEIC 校验 |
| 分享扩展具体 UTType | 源码审查 + 模拟器重试 | ✅ 改为优先 `public.heic` / `public.heif`，再取 provider 注册的具体图片类型，避免向抽象 `public.image` 要文件；模拟器仍停在读取阶段，未证明修复设备问题 |
| 分享扩展陈旧目录 | 源码审查 | ✅ 只清理 1 小时前的 `LingXiShare-*`，不会碰并发中的分享任务 |
| 分享扩展额度提示 | 源码 + 编译 catalog | ✅ 额度耗尽不再提供“重试”按钮，改为提示 00:00 重置或打开 App 了解 Pro |
| Keychain fail-closed | `KeychainQuotaTests` | ✅ 无共享组 entitlement 时报 `QuotaError.database`，不拆分账本 |
| 结果页延迟文案 | 源码 + 编译产物 | ✅ 硬编码中文改为 `result.deferredQuota`，四语言键齐全；未再次目视批量结果 |
| CI | `.github/workflows/ci.yml` | 🟡 新增 XcodeGen 一致性、四语言完整性、凭据扫描、Debug / Release、四套测试；本轮未在 GitHub 实际运行 |
| 版本 1.6.0 / build 7 | `project.yml` + 构建产物 | ✅ |
| 1.5 视觉基线 | 1.5 截图与源码 | ✅ 保持 iOS 语义表面、狐橙 `#E8A13A`、每屏最多一个强调填充；1.6 未改视觉层 |

## 5. 设备测试矩阵

状态：✅ 已验证（自动化 / 引擎层 / 模拟器）；🟡 已实现并通过编译，未运行；⚪ 未执行。
模拟器结果不能替代真机。

| # | 场景 | 预期 | 状态 |
| --- | --- | --- | --- |
| 1 | 12MP HEIC 原片 | 成功，另存新照片，原图不变 | ⚪ |
| 2 | 24MP HEIC 原片 | 成功 | ⚪ |
| 3 | 48MP Pro 原片（多 tile grid） | 成功，逐 tile 无损 | ✅ 1.2 引擎 54 tiles / 11 / 11；1.6 模拟器再次保存成功 |
| 4 | HDR / Gain Map 照片 | 成功，HDR 元数据保留 | ✅ 1.2 引擎 15 个 gain-map tiles；1.6 未改算法 |
| 5 | 夜景 / 人像 | 成功，纹理只追加不替换 | ⚪ |
| 6 | 已含纹理与颗粒 | 「无需处理」，不写入相册 | ✅ 自动化 + 模拟器 |
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
| 20 | 免费额度成功扣减 | 5 / 5 起，成功一次扣 1；重启仍保留 | ✅ 1.6 模拟器 5 / 5 → 4 / 5；自动化覆盖重启 |
| 21 | 失败 / 跳过不扣额度 | 额度不变 | ✅ 自动化（失败转换释放预留） |
| 22 | 额度耗尽页 | 显示升级与明天继续免费 | ✅ 1.6 英文 0 / 5 目视；按钮与说明本地化 |
| 23 | 批量超过剩余额度 | 提示实际可转数量，只转剩余 | ✅ 1.6 模拟器：9 选 6 可处理、剩 4；「仅处理 4 张」→ 成功 4 / 跳过 3 / 2 未处理 |
| 24 | 购买成功解锁 Pro | 首页显示 Pro 无限，重启保持 | ✅ StoreKit 自动化；1.2 本地购买 + 重启目视 |
| 25 | 取消 / 失败 / pending 购买 | 不授予 Pro；pending 批准后授予 | ✅ StoreKit 自动化 |
| 26 | 恢复购买 | 恢复 Pro | ✅ StoreKit 自动化 |
| 27 | 退款 / 撤销 | Pro 失效，回到免费额度 | ✅ StoreKit 自动化 |
| 28 | 商品加载失败 | 友好错误 + 重试，不显示虚构价格 | ✅ StoreKit 自动化；无配置启动目视 |
| 29 | 四地区价格 | USA / CHN / JPN / DEU 由 StoreKit 本地化 | ✅ StoreKit 自动化，本地配置 `$2.99` |
| 30 | 真实扣款 / App Store Sandbox | 真实交易可恢复、可退款 | ⚪ 未连接 App Store |
| 31 | 分享扩展额度共享 | 扩展转换后 App 额度减少 | 🟡 扩展可启动、取消可用；文件读取在模拟器停住，未完成转换 |
| 32 | 快捷指令额度共享 | 三个参数都受额度约束 | 🟡 代码共用 `ConversionService`；未真机 |
| 33 | 深色 / 浅色 | 真动态色，对比度 ≥ 4.5:1 | ✅ 1.6 深色首页 / Pro 页；1.5 其余页面 |
| 34 | Dynamic Type 大字号 | 布局不截断，主按钮仍可点 | ✅ 1.5 accessibility-extra-large 首页 3 页可滚动；其余页面未逐项 |
| 35 | Reduce Motion | 关闭循环光 / 扫边 / 缩放 | 🟡 已移除扫光、呼吸光与 Aura；代码审查，未运行 |
| 36 | VoiceOver | 大图、缩略图、进度、错误、额度可读 | ⚪ 未运行 |
| 37 | 快捷指令（保存 / 返回文件 / 仅检查） | 统计正确，文件可回传 | 🟡 已实现，未真机 |
| 38 | 分享扩展完整闭环 | 保存新照片，失败有本地化提示 | 🟡 模拟器停在读取阶段；不能写成通过 |
| 39 | 7 天签名过期 | 重新安装后可继续使用，照片不丢 | ⚪ |
| 40 | 折叠 / 紧凑屏幕 | 全部主操作与 footnote 一屏可见 | ✅ 1.6 iPhone Duo 466 × 678 pt 首页 5 / 5；选片 / 转换未跑通 |
| 41 | 设置与语言切换 | 五个语言选项，重启后生效；跟随系统可恢复 | ✅ 1.5 / 1.6 模拟器 zh-Hans ↔ en 往返 |
| 42 | 首次额度用尽提醒 | Pro 页只自动出现一次；之后安静额度页；重启保持 | ✅ 1.4 模拟器；1.6 代码未改 |
| 43 | 批量额度不足「仅转换 N 张」 | 只转剩余额度，统计正确，不静默扣费 | ✅ 1.6 模拟器；成功 4 / 跳过 3 / 2 未处理 |
| 44 | 跨入口抢最后额度 | 不把未处理写成失败；已保存保留 | ✅ `ConversionRunTests` + Keychain 最后槽位自动化；UI 未构造出现场 |
| 45 | 批量延后结果文案 | 四语言，不出现硬编码中文 | 🟡 已修复并编译验证；额度 0 后无法再次构造 5+ 可处理批量，未目视 |

## 6. 已知风险与未验证项

1. **没有真实 App Store 交易。** 自动化断言来自 `SKTestSession`，模拟器购买使用本地
   `Configuration.storekit`；真实商品、税务 / 银行信息、Sandbox 账号、退款到账时延都未验证。
   上线前必须按 `AppStoreRelease.md` 在 Sandbox 走一遍。
2. **没有 1.6 真机安装。** 分享扩展与快捷指令是否与主 App 共用 Keychain 额度，取决于
   真机 entitlements 与共享组是否正确展开；模拟器空 entitlements 的通过不能证明真机跨进程共享。
3. **App Group 路径未启用。** 免费 Personal Team 没有 App Group entitlement，当前真机
   默认走 Keychain；若使用付费团队并开启 App Group，SQLite 路径的跨进程事务需要在真机复测。
4. **权限拒绝页未目视。** 1.5 已按 Handoff 5.8 重写并通过编译，但模拟器 PhotosPicker
   自动授予受限访问，`simctl privacy` 无法把流程推进到 `.permissionDenied`。真机拒绝权限后
   需要复验三条恢复路径。
5. **分享扩展未完成端到端。** 模拟器从「照片」分享后一直停在“正在读取分享的照片”，
   7 秒内未回调；取消可用且不扣额度。把 provider 类型从抽象 `public.image` 改为具体
   UTType 后重试仍然停住，说明至少在当前 iOS 27.3 模拟器上不是简单的类型选择问题。
   没有崩溃日志，也没有在真机验证成功，不能写成通过。
6. **快捷指令未真机运行。** 取消、重名、额度停止逻辑已编译并有源码审查，但
   AppIntents 的返回文件、Shortcuts 参数与跨进程 Keychain 未实测。
7. **系统矩阵仍空白。** 12MP / 24MP、夜景、人像、RAW、iCloud 下载、权限受限、存储不足、
   取消 / 重试均未在 1.6 真机验收。
8. **Duo 只验证了首页。** 折叠屏上的选片、转换、结果页没有跑通；模拟器 PhotosPicker 在
   Duo 上出现输入无响应，不能据此判定 App 逻辑，也不能写成通过。
9. **批量延后文案未再次目视。** `ResultView.swift:332` 已改为本地化 key，编译产物中
   en / zh-Hant 值正确；但额度已到 0，无法再次构造“可处理数 > 剩余额度”的批次，未做最终截图。
10. `StylePortCoreTests` 有 2 项跳过，因为未设置 `STYLEPORT_FIXTURES` /
    `STYLEPORT_LIVE_VIDEO`，不是代码失败。
11. 免费 Personal Team 签名 7 天过期，属预期限制。
12. Keychain 账本用固定槽位表达每日额度；这是为跨进程原子性做的取舍，不做通用数据库。
    卸载重装不保证重置：Keychain 条目可能由系统保留，本版本也不会主动清除服务
    `com.lingxifox.LingXiStyle.quota`。
13. 本地 StoreKit 配置的 `$2.99` 仅用于测试；配置仍保留德文商品本地化，但 App UI 当前
    只提供 zh-Hans / zh-Hant / en / ja 四种语言。
14. 通过 `simctl launch` 启动不会附加 `Configuration.storekit`，Pro 页可能显示商品不可用；
    这是真实的加载失败路径，不代表线上商品缺失。
15. **CI 未在 GitHub 实际运行。** `.github/workflows/ci.yml` 已通过本地 YAML 审查，但
    macOS runner、Xcode 16.4 与 iPhone 16 模拟器组合未实际跑过。

## 7. 建议的验收顺序

1. 用付费团队或 Personal Team 在真机安装 1.6，确认首页显示 5 / 5，首次启动不弹付费页。
2. 转换 1 张，确认扣到 4 / 5；杀掉 App 重开，确认仍为 4 / 5。
3. 用损坏 HEIC、JPEG、Live Photo、已含纹理与颗粒照片各试一次，确认全部不扣额度。
4. 连续转换到第 6 张，确认首次用尽只自动弹一次 Pro，重启后再触发只打开安静额度页；
   用 3 张批量但只剩 1 张额度，确认只转 1 张，并检查结果页的延后文案。
5. 在 Sandbox 购买 Pro，确认首页切换为无限、重启保持；再测恢复购买与退款。
6. 用分享扩展和快捷指令各转换 1 张，回到主 App 确认额度同步减少（真机跨进程关键项）。
   分享扩展若仍停在读取阶段，记录系统日志与 provider 类型，不要用模拟器结果判定代码通过。
7. 拒绝相册权限，确认权限页三条恢复路径；在深色、最大 Dynamic Type、Reduce Motion、
   VoiceOver 下走首页、设置页、Pro 页与额度耗尽页。
8. 最后补 12MP / 24MP、iCloud、存储不足、取消 / 重试、横竖屏与 Duo 全流程矩阵。
