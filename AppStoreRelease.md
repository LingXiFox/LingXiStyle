# App Store 发布配置（纹粒 / Texel 1.9.1）

这份文档只描述**若要发布到 App Store**时需要完成的 App Store Connect 与签名配置。
仓库本身仍然只提供源码，不附带 IPA、TestFlight 包或真实商品。

## 0. 先分清三种价格 / 交易环境

| 环境 | 交易来源 | 是否真实扣款 | 用途 |
| --- | --- | --- | --- |
| Xcode 本地 StoreKit 配置 | 仓库根目录 `Configuration.storekit` | 否 | 模拟器 / 单元测试，验证购买、恢复、退款 |
| App Store Sandbox | App Store Connect 商品 + Sandbox 测试账号 | 否 | 真机验证完整 StoreKit 流程 |
| App Store 生产 | App Store Connect 审核通过的商品 | 是 | 最终用户购买 |

`Configuration.storekit` 里的 `2.99` 只是本地测试价格，不是任何地区的真实售价。
UI 与测试都不得把它当作生产价格。

## 1. 前置条件

- 加入 Apple Developer Program（付费）。免费 Personal Team 不能创建可售内购，也不能上架。
- 在 App Store Connect 接受 **Paid Apps Agreement**。
- 完成税务信息与银行账户；未完成时商品可能显示为不可售。
- App 的 Bundle ID 与仓库一致：`com.lingxifox.Texel`。
- 分享扩展 Bundle ID：`com.lingxifox.Texel.Share`。
- 若要跨 App / 分享扩展共享免费额度，两个 target 必须使用同一个 Keychain Access Group；
  仓库 entitlements 使用 `$(AppIdentifierPrefix)com.lingxifox.Texel.shared`。
  免费 Personal Team 的个人资料没有 App Groups，因此默认不依赖 App Group。
- iPad 与 iPhone 共用 `com.lingxifox.Texel`（`TARGETED_DEVICE_FAMILY = "1,2"`）。
- macOS 版是独立 target `TexelMac`，Bundle ID 与 iOS / iPadOS 同为 `com.lingxifox.Texel`；
  使用同一条 App Store Connect 记录与 Universal Purchase，保留独立原生桌面界面。
  上架前需在现有记录中添加 macOS 平台，步骤见 `docs/app-store/universal-purchase.md`。

## 2. 创建内购项目（四种）

在 App Store Connect → 你的 App → **App 内购买项目**。1.9.1 需要四种商品，权益相同、期限不同：

| 类型 | Product ID | 说明 |
| --- | --- | --- |
| 非消耗型 Non-Consumable | `com.lingxifox.LingXiStyle.pro` | 永久版，沿用 1.8 商品，已购用户不受影响 |
| 非续期订阅 Non-Renewing Subscription | `com.lingxifox.LingXiStyle.pro.day` | 24 小时日卡，一次性购买 |
| 自动续期订阅（订阅组） | `com.lingxifox.LingXiStyle.pro.weekly` | 周订阅 |
| 自动续期订阅（同一订阅组） | `com.lingxifox.LingXiStyle.pro.monthly` | 月订阅 |

1. 永久版类型必须是 **非消耗型**，Product ID 精确为 `com.lingxifox.LingXiStyle.pro`。
2. 日卡类型必须是 **非续期订阅**，不自动续订；24 小时权益由 App 按已验证交易的购买时间计算。
3. 周 / 月订阅放在**同一个订阅组、同一等级（1）**，因为权益完全相同、仅期限不同；不同期限的切换由系统处理。
4. 参考名称统一使用 `Texel Pro`，本地化至少填写简体中文，建议同时填写繁体中文、英文、日文：
   - 简体中文：`纹粒 Pro` / `解锁不限张数，支持日卡、订阅或永久。`
   - 繁體中文：`Texel Pro` / `解鎖不限張數，支援日卡、訂閱或永久。`
   - English: `Texel Pro` / `Unlock unlimited photos with a day pass, a subscription, or lifetime.`
   - 日本語：`Texel Pro` / `日券・サブスク・買い切りのいずれかで枚数無制限。`
5. 上传审核截图（Pro 方案页四档、购买按钮、恢复购买、管理订阅）。
6. 价格：先设置基准地区价格，其他地区使用 Apple 自动定价或手动覆盖。
7. 商品状态必须为 **Ready to Submit / 已准备提交**，并随 App 版本一起提交审核。

App 代码只读取 `Product.displayPrice`，不包含任何美元 / 人民币 / 日元 / 欧元硬编码。
调整基准价或地区价不需要改代码、不需要重新发版。

## 3. Xcode 签名与能力

1. 在 Xcode → target `LingXiStyle` → Signing & Capabilities，选择付费 Team。
2. 为 `LingXiStyle` 与 `LingXiStyleShare` 使用相同的 Team。
3. 确认两个 target 的 Keychain Sharing 都包含：
   `$(AppIdentifierPrefix)com.lingxifox.Texel.shared`
4. 不需要 App Groups；免费额度默认使用 Keychain 槽位账本。
5. 真实内购不需要额外的 StoreKit entitlement，但需要 App Store Connect 商品与有效签名。
6. `TexelMac`：选择同一 Team，启用 App Sandbox 与
   `com.apple.security.files.user-selected.read-write`、`files.bookmarks.app-scope`；
   entitlements 见 `Mac/Resources/TexelMac.entitlements`，隐私清单见 `Mac/Resources/PrivacyInfo.xcprivacy`。
7. iOS 与 iPadOS 共用 iPhone 构建（`TARGETED_DEVICE_FAMILY = "1,2"`），宽屏双栏仍由 Duo 内屏的
   regular size class 触发；iPad 使用两栏首页与居中内容列。

## 4. 本地与 Sandbox 验证

### 4.1 模拟器（仓库默认）

`project.yml` 已把 `Configuration.storekit` 绑定到 Debug 的 `LingXiStyle` 与 `TexelMac` scheme。
执行 `xcodegen generate` 后，用 Xcode Run 启动任一 App，购买面板会使用本地配置，不产生真实交易。
本地配置包含四种商品：永久 2.99、日卡 0.49、周 0.99、月 1.99，这些只是测试显示价，
这些本地测试价与生产定价分开管理。2026-11-13 主人已批准美国基准价：日卡 $0.49、周 $0.99、月 $1.99、永久 $7.99；线上操作与回读见本轮发布报告。

自动化测试：

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiPurchaseTests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/LingXiStyle-PurchaseDD test
```

覆盖商品加载、地区价格、购买成功 / 取消 / 失败、待批准、恢复、重启后权益、
退款 / 撤销、重复回调、商品加载失败重试、跨入口额度，以及 100% 免费 Offer Code
（`testFreeOfferCodeGrantsVerifiedPro`）。

Offer Code 测试的运行时限制：

- Xcode 16.4 / iOS 18.5 SDK 没有 `.codeOffer` API，该测试被 `#if compiler(>=6.2)` 编译排除。
- iOS 26 的 StoreKitTest 会忽略本地 Offer Code 并按列表价收款，该测试在运行期 `XCTSkip`。
- 本机 iOS 27.3 实际执行通过：交易价格 0、验签通过、`StoreKitEntitlementProvider.isPro()`
  为真、新 `PurchaseManager` 启动即 Pro。
- 因此 App Store Connect 的官方 Offer Code 兑换仍需按 4.3 在 Sandbox / 生产复验。

### 4.2 真机 Sandbox

1. App Store Connect → 用户和访问 → Sandbox → 测试员，新建 Sandbox 账号。
2. 真机退出日常 Apple ID 的 App Store 登录，用 Sandbox 账号购买。
3. 验证：购买成功、取消、待批准、恢复购买、删除重装后恢复、退款后权益回收。
4. 订阅额外验证：日卡 24 小时后回落到免费额度；周 / 月订阅在 Sandbox 中加速续订、到期与升级 / 降级；
   订阅管理页能打开系统「管理订阅」；取消后到期前权益保持，到期后回落。
5. 同一 Apple ID 在 iPhone、iPad 与 Mac 上分别恢复购买，确认权益一致。
6. 退款可在 App Store Connect → 用户与访问 → Sandbox → 交易记录中模拟；或使用
   StoreKitTest 的 `refundTransaction` 做自动化回归。
7. 真机必须验证 App 与分享扩展共享额度。Xcode 自动签名构建的模拟器产物会生成
   `*-Simulated.xcent`，1.7.1 已用签名模拟器与集成测试验证 App / 扩展同组同步；但这不等于真机 distribution
   签名通过，真机仍需复验。

### 4.3 官方 100% Offer Code

1. 在 App Store Connect → App → App 内购买项目 → 选择
   `com.lingxifox.LingXiStyle.pro` → **Offer Codes / 优惠代码**。
2. 创建 100% 折扣、免费兑换的代码；设置有效期、兑换上限与分发方式。
3. 生产环境的 Offer Code 受商品状态与 App 发布状态约束；商品需可售并随版本审核。
4. 用 Sandbox 账号兑换后，确认 `Transaction.currentEntitlements` 出现该商品、
   Pro 页显示已解锁，删除重装后「恢复购买」仍能恢复。
5. 本地 `Configuration.storekit` 的 `DEVELOPER_FREE` 只用于自动化；
   生产代码不得内置免费解锁旁路、固定兑换码或开发者账号白名单。

授权逻辑不检查交易价格，因此 0 元交易会被接受；这是支持官方 Offer Code 的前提，
也意味着任何绕过 StoreKit 验签的“免费 Pro”实现都是错误。生产兑换必须使用 Apple 官方
Offer Code，代码中不得出现固定兑换码、开发者账号白名单或隐藏开关。

## 5. 发布前检查清单

- [ ] 版本号 `1.9.1`、Build `11`（或更高）已写入 `project.yml`。
- [ ] `xcodegen generate` 后 Debug scheme 仍带 `Configuration.storekit`。
- [ ] `LingXiKitTests`、`LingXiPurchaseTests`、`LingXiEngineTests`、`StylePortCoreTests`、`LingXiIntegrationTests`、`LingXiUITests`、`LingXiMacPipelineTests` 全绿（本机 168 项 / 3 跳过 / 0 失败）。
- [ ] 已在 App Store Connect 现有 Texel 记录中添加 macOS 平台，并按 `docs/app-store/universal-purchase.md` 检查 Bundle ID、能力与四商品共用。
- [ ] Release 构建不包含 StoreKit 测试配置。
- [ ] 商品 ID、类型、本地化、价格、审核截图已填。
- [ ] Paid Apps Agreement、税务、银行信息完成。
- [ ] Pro 页面只显示 `Product.displayPrice`；加载失败显示错误与重试，不显示假价格。
- [ ] 免费额度 5 张 / 本地自然日；失败、跳过、不兼容不扣额度。
- [ ] 额度耗尽页可继续免费到明天，也可进入 Pro；批量超额度只转剩余张数。
- [ ] 恢复购买、退款 / 撤销、待批准、未完成交易均有本地化提示。
- [ ] 首次启动不强制弹付费页。
- [ ] 分享扩展与快捷指令同样受额度约束。
- [ ] 1.5 / 1.7 视觉：iOS 语义表面、狐橙 `#E8A13A`、每屏最多一个强调填充；无渐变边框 / 扫光 / 呼吸光。
- [ ] 跨入口额度竞态：另一入口抢走最后额度时，未处理项显示为延后，不记失败。
- [ ] Keychain 无共享组 entitlement 时 fail-closed，不静默拆成两套账本。
- [ ] 分享扩展在真机完成读取、转换、保存；另测取消与 15 秒超时。
- [ ] 集成测试宿主已授权相册，37 条真实 HEIC / 实况照片 / 分享 / 快捷指令 / 保险箱测试通过。
- [ ] XCUITest 教程分步、首页、设置与 Pro 入口冒烟通过；Duo 内屏双栏、设置与 Pro sheet 实测通过（1.9.1 起 iPad 也属于发布支持范围）。
- [x] GitHub Actions CI 已成功运行：[run 42435430433](https://github.com/LingXiFox/LingXiStyle/actions/runs/42435430433)
      （1.7.1 / commit `365abf5`；Policy、macOS 单测、iOS 18.5、iOS 26.x 全绿；两条集成均 29/29、0 跳过）。
      1.7.0 的 [run 42371186297](https://github.com/LingXiFox/LingXiStyle/actions/runs/42371186297) 亦全绿。
- [ ] 设置页 Pro 行显示「解锁不限张数，支持日卡、订阅或永久。」或已购状态，不显示价格。
- [ ] 成果保险箱：保留期、占用、剩余时间、重存不扣额度、删除与清理过期均有四语言文案。
- [ ] 任务历史：成功 / 部分完成 / 失败 / 取消 / 中断状态可读，失败可重试，中断任务启动后可见。
- [ ] 免费体验每台设备一次，卸载重装不重置，到期回到实际权益。
- [ ] iPad 两栏首页、多窗口与拖放；Mac 导入 / 批量 / 自定义导出文件夹 / 快捷键。
- [ ] 浅色 / 深色、Dynamic Type、Reduce Motion、VoiceOver 通过。
- [ ] 四语言商店文案与可部署隐私 / 支持页已复核：`docs/app-store/listing.md`、`docs/privacy/index.html`、`docs/support/index.html`。
- [ ] 真实 App 截图已按 `docs/app-store/screenshots.md` 捕获；未使用 `Tests/Fixtures/IMG_5296.HEIC` 或合成图。
- [ ] 中国大陆 App 备案 / ICP 信息已按 `docs/app-store/china-mainland.md` 完成；未取得真实号码前不提交中国大陆区。
- [x] App target 已提供 `PrivacyInfo.xcprivacy`（`UserDefaults` / `CA92.1`）；Share Extension 已提供独立清单（`FileTimestamp` / `C617.1`）。
- [ ] 隐私说明、支持 URL、审核备注已填写。
- [x] 1.8.1 Release archive 已生成（1.8.1 / build 10，`Apple Distribution` 签名，IPA 无本地 StoreKit 配置）。
- [x] 此前工程验收的 iOS / macOS 未签名归档均为 1.9.1 / build 11；正式 iOS 签名上传见下一条，Mac 仍未做 distribution 签名。
- [x] 2026-11-13 已上传并关联 iOS / iPadOS 1.9.1（11）distribution 签名构建，Apple 处理为 VALID；保持未提交审核。详见 [发布记录](docs/app-store/release-report-2026-11-13.md)。

## 6. 审核备注建议

```
Texel Pro unlocks unlimited photo conversions. Four products share the same
benefits and differ only in duration: a lifetime non-consumable (com.lingxifox.LingXiStyle.pro),
a 24-hour non-renewing day pass (...pro.day), and weekly / monthly auto-renewable
subscriptions (...pro.weekly / ...pro.monthly) in one subscription group.
Free users can keep using 5 conversions per local calendar day. New users may claim
one 24-hour Pro trial per device without subscribing or paying. All conversions run
on-device; no account or server is required. Restore Purchases and Manage
Subscriptions are available on the Pro page. Subscription terms and cancellation
are shown before purchase; deleting the app does not cancel a subscription.
```

## 7. 已知边界

- 本仓库不分发 IPA；真实商品只在 App Store 生产环境扣款。
- 免费 Personal Team 的 7 天签名只适合源码自用，不能用于上架或真实内购。
- 本地 StoreKit 配置的 `$2.99` 只是测试显示，不是定价建议。
- 1.7.1 保留分享扩展阻塞修复，并新增 12 条取消 / 超时 / 回退 / 重试状态机测试；
  1.7.0 已在 iOS 27.3 模拟器完成原片 → 读取 → 转换 → 保存 → 额度同步；真机分享扩展仍未验证。
- 1.7.1 新增真实 48MP HEIC 端到端集成测试与 XCUITest 启动冒烟；本机六套测试合计
  98 项执行 / 96 通过 / 2 跳过。Duo 仅验证首页、设置与 Pro 页。
- 1.8.1 本机六套测试 118 项执行 / 0 失败 / 2 跳过；实况双模式、106 帧额度、9 步教程、Duo 外屏全流程与 Duo 内屏双栏已验证。
- 1.9.1 本机七套测试 168 项 / 3 跳过 / 0 失败；iOS / iPadOS 与 macOS Debug、Release 构建通过；无真机、无 iOS 18 / 26 运行时，
  真实交易与订阅续订 / 退款、iPad / Mac 完整人工流程未验证。
- 通用购买的代码侧配置已完成：`TexelMac` 与 iOS / iPadOS 同为 `com.lingxifox.Texel`，四个商品 ID 共用；
  App Store Connect 现有记录添加 macOS 平台、上传 Mac 构建仍为人工步骤，详见 `docs/app-store/universal-purchase.md`。
  在完成线上平台配置前，不得宣称 Mac 版已经可以在 App Store 恢复 iOS 购买。
- 100% Offer Code 的生产兑换依赖 App Store Connect 配置与商品可发放状态；
  本地配置不能替代生产资格检查。
- 若未来改用 App Group + SQLite 作为额度存储，必须同时为 App 与扩展申请 App Group，
  并重新验证签名；当前实现不依赖这条路径。
