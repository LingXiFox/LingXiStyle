# App Store 发布配置（纹粒 / Texel 1.6）

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
- App 的 Bundle ID 与仓库一致：`com.lingxifox.LingXiStyle`。
- 分享扩展 Bundle ID：`com.lingxifox.LingXiStyle.Share`。
- 若要跨 App / 分享扩展共享免费额度，两个 target 必须使用同一个 Keychain Access Group；
  仓库 entitlements 使用 `$(AppIdentifierPrefix)com.lingxifox.LingXiStyle.shared`。
  免费 Personal Team 的个人资料没有 App Groups，因此默认不依赖 App Group。

## 2. 创建非消耗型商品

在 App Store Connect → 你的 App → **App 内购买项目**：

1. 类型选择 **非消耗型（Non-Consumable）**。
2. Product ID 必须精确为：

   ```
   com.lingxifox.LingXiStyle.pro
   ```

3. 参考名称：`Texel Pro`。
4. 本地化至少填写简体中文；建议同时填写繁体中文、英文、日文，德文可选：
   - 简体中文：`纹粒 Pro` / `一次购买，永久不限张数。`
   - 繁體中文：`Texel Pro` / `一次購買，永久不限張數。`
   - English: `Texel Pro` / `One purchase. Unlimited photos, forever.`
   - 日本語：`Texel Pro` / `一度の購入で、写真はいつでも無制限。`
   - Deutsch（可选）：`Texel Pro` / `Einmal kaufen. Unbegrenzte Fotos, für immer.`
5. 上传审核截图（Pro 页面 + 购买按钮 + 恢复购买）。
6. 价格：先设置一个基准地区价格，其他地区使用 Apple 的自动定价，或按地区手动覆盖。
7. 商品状态必须为 **Ready to Submit / 已准备提交**，并随 App 版本一起提交审核。

App 代码只读取 `Product.displayPrice`，不包含任何美元 / 人民币 / 日元 / 欧元硬编码。
调整基准价或地区价不需要改代码、不需要重新发版。

## 3. Xcode 签名与能力

1. 在 Xcode → target `LingXiStyle` → Signing & Capabilities，选择付费 Team。
2. 为 `LingXiStyle` 与 `LingXiStyleShare` 使用相同的 Team。
3. 确认两个 target 的 Keychain Sharing 都包含：
   `$(AppIdentifierPrefix)com.lingxifox.LingXiStyle.shared`
4. 不需要 App Groups；免费额度默认使用 Keychain 槽位账本。
5. 真实内购不需要额外的 StoreKit entitlement，但需要 App Store Connect 商品与有效签名。

## 4. 本地与 Sandbox 验证

### 4.1 模拟器（仓库默认）

`project.yml` 已把 `Configuration.storekit` 绑定到 Debug 的 `LingXiStyle` scheme。
执行 `xcodegen generate` 后，用 Xcode Run 启动 App，购买面板会使用本地配置，不产生真实交易。

自动化测试：

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiPurchaseTests \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/LingXiStyle-PurchaseDD test
```

覆盖商品加载、地区价格、购买成功 / 取消 / 失败、待批准、恢复、重启后权益、
退款 / 撤销、重复回调、商品加载失败重试与跨入口额度。

### 4.2 真机 Sandbox

1. App Store Connect → 用户和访问 → Sandbox → 测试员，新建 Sandbox 账号。
2. 真机退出日常 Apple ID 的 App Store 登录，用 Sandbox 账号购买。
3. 验证：购买成功、取消、待批准、恢复购买、删除重装后恢复、退款后权益回收。
4. 退款可在 App Store Connect → 用户与访问 → Sandbox → 交易记录中模拟；或使用
   StoreKitTest 的 `refundTransaction` 做自动化回归。
5. 真机必须验证 App 与分享扩展共享额度；模拟器签名构建的 entitlements 为空，
   只能验证 App 进程内的持久化，不能写成跨进程共享已验证。

## 5. 发布前检查清单

- [ ] 版本号 `1.6.0`、Build `7`（或更高）已写入 `project.yml`。
- [ ] `xcodegen generate` 后 Debug scheme 仍带 `Configuration.storekit`。
- [ ] `LingXiKitTests`、`LingXiPurchaseTests`、`LingXiEngineTests`、`StylePortCoreTests` 全绿。
- [ ] Release 构建不包含 StoreKit 测试配置。
- [ ] 商品 ID、类型、本地化、价格、审核截图已填。
- [ ] Paid Apps Agreement、税务、银行信息完成。
- [ ] Pro 页面只显示 `Product.displayPrice`；加载失败显示错误与重试，不显示假价格。
- [ ] 免费额度 5 张 / 本地自然日；失败、跳过、不兼容不扣额度。
- [ ] 额度耗尽页可继续免费到明天，也可进入 Pro；批量超额度只转剩余张数。
- [ ] 恢复购买、退款 / 撤销、待批准、未完成交易均有本地化提示。
- [ ] 首次启动不强制弹付费页。
- [ ] 分享扩展与快捷指令同样受额度约束。
- [ ] 1.5 / 1.6 视觉：iOS 语义表面、狐橙 `#E8A13A`、每屏最多一个强调填充；无渐变边框 / 扫光 / 呼吸光。
- [ ] 跨入口额度竞态：另一入口抢走最后额度时，未处理项显示为延后，不记失败。
- [ ] Keychain 无共享组 entitlement 时 fail-closed，不静默拆成两套账本。
- [ ] 分享扩展在真机完成一次完整分享转换，不再停在“正在读取分享的照片”。
- [ ] GitHub Actions CI 至少成功运行一次，XcodeGen 生成工程与仓库一致。
- [ ] 设置页 Pro 行只显示「一次购买，永久不限张数。」或已购状态，不显示价格。
- [ ] 浅色 / 深色、Dynamic Type、Reduce Motion、VoiceOver 通过。
- [ ] 隐私说明、支持 URL、审核备注已填写。
- [ ] Archive 使用 Release、正确 Team、上传 App Store Connect。

## 6. 审核备注建议

```
Texel Pro is a one-time non-consumable in-app purchase that removes the
free daily limit of 5 successful photo conversions. It is not a subscription.
Free users can keep using 5 conversions per local calendar day. All conversions
run on-device; no account or server is required. Restore Purchases is available
on the Pro page.
```

## 7. 已知边界

- 本仓库不分发 IPA；真实商品只在 App Store 生产环境扣款。
- 免费 Personal Team 的 7 天签名只适合源码自用，不能用于上架或真实内购。
- 本地 StoreKit 配置的 `$2.99` 只是测试显示，不是定价建议。
- 1.6 的分享扩展在 iOS 27.3 模拟器上会停在“正在读取分享的照片”，取消可用且不扣额度；
  未证明是设备问题，也未完成真机端到端验证。上线前必须在真机复验。
- 若未来改用 App Group + SQLite 作为额度存储，必须同时为 App 与扩展申请 App Group，
  并重新验证签名；当前实现不依赖这条路径。
