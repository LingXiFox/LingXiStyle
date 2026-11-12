# Texel 通用购买（Universal Purchase）配置说明

状态：代码与本地工程已按通用购买调整；App Store Connect 的 macOS 平台仍需主人手动添加。本文不代替 Apple 的审核与商务配置，也不包含任何线上改动。

## 1. 目标身份

| 项目 | 值 |
| --- | --- |
| App Store Connect 应用记录 | 现有 Texel 记录（纹粒 / Texel） |
| iPhone / iPad Bundle ID | `com.lingxifox.Texel` |
| macOS Bundle ID | `com.lingxifox.Texel`（与 iOS 相同） |
| macOS target | `TexelMac`，保留独立原生 SwiftUI 界面 |
| 分享扩展 Bundle ID | `com.lingxifox.Texel.Share`（扩展身份，不单独上架） |
| Team | `R9UJHHAZQ4` |
| Keychain 共享组 | `$(AppIdentifierPrefix)com.lingxifox.Texel.shared` |
| 永久 Pro 商品 ID | `com.lingxifox.LingXiStyle.pro`（保持不变） |
| 日卡商品 ID | `com.lingxifox.LingXiStyle.pro.day` |
| 周订阅商品 ID | `com.lingxifox.LingXiStyle.pro.weekly` |
| 月订阅商品 ID | `com.lingxifox.LingXiStyle.pro.monthly` |

iOS、iPadOS 与 macOS 必须使用同一个 Bundle ID，才能归入同一条 App Store Connect 记录并共享 Universal Purchase。macOS 端仍是独立 target 与独立桌面界面，不是 Mac Catalyst，也不是把 iPad 界面直接搬到 Mac。

## 2. 在 App Store Connect 添加 macOS 平台（手动）

以下步骤只能在 App Store Connect 网页或 Transporter 中由有权限的账号完成。本轮没有创建新记录、没有上传构建、没有提交审核。

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)，进入「我的 App」→ 选择现有 Texel / 纹粒记录。
2. 打开「App 信息」，在「平台」或「Platforms」区域选择添加平台，勾选 macOS。若界面只显示 iOS，使用页面上的「添加平台 / Add Platform」入口；不要新建另一条 App 记录。
3. 确认应用记录下的 Bundle ID 为 `com.lingxifox.Texel`。macOS 构建上传后会出现在同一记录的 macOS 平台下。
4. 在「App 信息」补充 macOS 所需的分类、年龄分级、版权、隐私政策 URL 与支持 URL；macOS 分类使用摄影（`public.app-category.photography`）。
5. 在「价格与销售范围」确认 macOS 与 iOS 使用同一销售范围；Universal Purchase 下同一 App 记录的各平台共享价格与 App 内购买项目。
6. 在「App 内购买项目」确认四个商品仍挂在同一条应用记录下。不要为 macOS 新建一套商品 ID；否则会破坏跨平台权益。
7. 在「功能」→「App 内购买项目」检查四个商品的状态、价格层级与本地化显示名称。正式改价与启用新商品需要主人另行授权，本文不修改线上价格。
8. 为 macOS 准备独立的 1.9.1 截图、描述与关键词；不要复用 iPhone 截图冒充 macOS 界面。

## 3. 签名与能力

### iOS / iPadOS 主 App

- `App/Resources/LingXiStyle.entitlements`：Keychain Sharing，组为 `$(AppIdentifierPrefix)com.lingxifox.Texel.shared`。
- `App/Resources/Info.plist`：`LingXiKeychainGroup` 指向同一共享组。
- iPad 已在 `TARGETED_DEVICE_FAMILY = "1,2"` 中；支持四方向、多窗口与拖放。

### macOS

- `Mac/Resources/TexelMac.entitlements`：App Sandbox、用户选择文件读写、安全书签、Keychain Sharing（同一共享组）。
- `Mac/Resources/Info.plist`：`LingXiKeychainGroup` 指向同一共享组；`LSApplicationCategoryType = public.app-category.photography`。
- macOS 不使用 App Group 数据库；额度会使用 Keychain 账本。Pro 权益来自 StoreKit 已验证交易，不依赖 iOS 的 App Group。
- Release 归档需要 macOS App Store 的 provisioning profile：`TEXEL_MAC_APP_STORE_PROFILE`。在 Xcode 中选择自动签名或提供对应 profile；不得把 Team 凭据或 profile 提交到仓库。

### 分享扩展

- `ShareExtension/Resources/LingXiStyleShare.entitlements` 使用同一 Keychain 共享组。
- 分享扩展的 `Bundle.main` 是 `com.lingxifox.Texel.Share`；日卡/体验账本通过 `ProLedgerScope.ownerBundleID` 映射回主 App 的 `com.lingxifox.Texel`，因此扩展能读到主 App 的体验与日卡状态。
- 分享扩展不共享 App 保险箱或任务历史；这是容器隔离的已知限制。

## 4. 本机构建与归档

```bash
xcodegen generate

# iOS / iPadOS Debug
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'generic/platform=iOS' build

# macOS Debug
xcodebuild -project LingXiStyle.xcodeproj -scheme TexelMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build

# macOS Release 归档（需要有效 Team 与 profile）
xcodebuild -project LingXiStyle.xcodeproj -scheme TexelMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/TexelMac.xcarchive archive
```

归档后用 Xcode Organizer 或 `xcodebuild -exportArchive` 导出 Mac App Store 包。上传前确认：

- 归档中的 `CFBundleIdentifier` 为 `com.lingxifox.Texel`。
- 签名包含 Keychain Sharing 能力与 `com.lingxifox.Texel.shared` 组。
- 版本号与 build 号与 iOS 1.9.1 / 11 一致，或在 App Store Connect 中按平台分别递增。
- 未把 `Configuration.storekit` 或开发购买旁路带入 Release。

## 5. 商品与权益验证清单

- [ ] 同一 Apple ID 在 iPhone 购买永久 Pro 后，Mac 启动即可识别 `Transaction.currentEntitlements`，不需要再次购买。
- [ ] Mac 购买永久 Pro 后，iPhone / iPad 同样识别；商品 ID 仍为 `com.lingxifox.LingXiStyle.pro`。
- [ ] 日卡在设备 A 购买后，设备 B 通过 `Transaction.all` 中同一 Apple ID 的非续期交易恢复，剩余时间以 Apple `purchaseDate` 为基准。
- [ ] 日卡退款/撤销后，两端都不再显示 Pro；本机 Keychain 镜像不能覆盖已撤销交易。
- [ ] 周/月订阅购买、续订、切换、过期、退款、撤销与恢复购买均正确；切换套餐时不会同时保留两个同权益套餐。
- [ ] 已有永久 Pro 的用户不会看到重复购买同权益商品的诱导；订阅用户可以看到「管理订阅」入口。
- [ ] 24 小时体验仍是每设备一次、主动领取、不自动扣费；卸载重装不会重置本机领取记录（Keychain 持久化）。
- [ ] 价格显示只读 `Product.displayPrice`；正式售价仍以 App Store Connect 为准。

## 6. 已知边界

1. **App Store Connect 操作未执行**：本轮只改本地工程与文档，未创建线上记录、未上传构建、未提交审核。
2. **Mac 旧 Bundle ID 的迁移**：1.9.1 之前本地 Mac 构建曾使用 `com.lingxifox.Texel.Mac`，但该构建从未上架；若外部曾有测试包，Mac App Store 不会把它当作同一应用升级。正式分发以本文件中的统一 Bundle ID 为准。
3. **日卡跨设备依赖 StoreKit 交易历史**：当前用 `Transaction.all` 恢复同一 Apple ID 的非续期交易；Keychain 只是本机镜像与离线兜底，不是跨设备存储。没有引入账号系统或外部服务。
4. **体验防重复是尽力而为**：Keychain 能抵抗普通卸载重装，但不能抵抗抹机、改设备标识或越狱级操作；不宣称绝对防刷。
5. **价格未改**：永久 Pro 线上仍为 $2.99，191.md 规划的 $7.99 未获授权，未做任何线上改价。
