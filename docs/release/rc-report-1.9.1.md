# Texel 1.9.1 RC 验收报告

- 日期：2026-11-12
- 分支：`feature/texel-1.9.1`
- RC 代码提交：`d983ae3`（`feat(1.9.1): finish universal purchase and RC hardening`）
- 基线：`c534b1b`（1.9.1 前一轮交付）
- 版本：1.9.1（build 11）
- 报告性质：工程 RC 验收；不是提审包，不代表真机或真实交易通过。

## 1. 分支、提交与工作区

- 当前分支为 `feature/texel-1.9.1`，本轮 RC 代码提交为 `d983ae3`，已推送到 `origin`。
- 本轮共 25 个文件、+531 / -68：通用购买 Bundle ID 与 Keychain 组、多档 Pro 与跨设备日卡、Pro 页面去重复推销、任务恢复守卫、保险箱自动清理、iPad 横屏测试，以及对应文档。
- 工作区只剩 3 个仓库原有未跟踪 docs 资产，未纳入提交：
  `docs/Test Photo/`、`docs/Texel_ICP_Exemption_Declaration_Unsigned.pdf`、`docs/纹粒 Texel：质感影像上线.png`。
- 未执行：合并 main、创建标签、发布、提审、线上改价、真实收费、上传构建。

## 2. 本轮修复与提交内容

| 方向 | 改动 |
| --- | --- |
| 通用购买 | `TexelMac` 的 Bundle ID 从 `com.lingxifox.Texel.Mac` 改为 `com.lingxifox.Texel`；Mac Info.plist 与 entitlements 加同一 Keychain 共享组；iOS / iPadOS / macOS 共用四个商品 ID；归档产物 Bundle ID 已复核一致 |
| 日卡跨设备 | `StoreKitEntitlementProvider.snapshot()` 改用 `Transaction.all`；日卡以 Apple 交易 `purchaseDate + 24h` 计算，不依赖本机 Keychain 时间；本地 Keychain 只作镜像，交易撤销时清理匹配镜像 |
| 订阅权益 | 永久优先；否则取到期最晚的活跃订阅；过期 / 撤销交易被过滤；有永久或活跃订阅时购买页不再推销日卡 / 订阅 |
| 额度与任务 | `recoverInterruptedTasks` 增加当前任务守卫；`refreshVault` 自动清理过期成果并跳过活跃任务；成功保存但没有预留时不再写 `committed` |
| 分享扩展权益 | `ProLedgerScope.ownerBundleID` 把 `com.lingxifox.Texel.Share` 映射到主 App，扩展能读到主 App 的体验 / 日卡状态 |
| 额度存储 | `KeychainQuotaStore.accessGroup(from:)` 校验 10 位团队前缀；未展开的 `com.lingxifox.Texel.shared` 返回 nil，ad-hoc / unsigned 构建回退默认 Keychain，不 fail-open 到另一套账本 |
| iPad | 新增 `Tests/LingXiUITests/IPadLayoutTests.swift`；横屏断言窗口宽大于高；竖屏 2048×2732、横屏 2732×2048 均两栏、额度 5/5 |
| macOS | Pro 页四档计划、试用、法务、额度显示；Finder 导入 HEIC 到队列；设置、保险箱、历史可打开 |
| 文档 | `docs/app-store/universal-purchase.md`、`docs/app-store/screenshots-1.9.1.md`、更新 README / AppStoreRelease / TEST_REPORT / AGENTS / listing / release notes |

## 3. 三平台构建、测试与安装

### 构建

| 目标 | 配置 | 结果 |
| --- | --- | --- |
| iOS（通用设备） | Debug | BUILD SUCCEEDED，0 error |
| iOS（通用设备） | Release | BUILD SUCCEEDED，0 error |
| TexelMac（macOS arm64） | Debug | BUILD SUCCEEDED，0 error |
| TexelMac（macOS arm64） | Release | BUILD SUCCEEDED，0 error |
| iPad 13 模拟器 | Debug 签名构建 | 安装并启动成功 |

四套构建均未出现 Swift 源码 warning；只有 `appintentsmetadataprocessor` 的常规提示。

### 归档

| 平台 | 产物 | 结果 |
| --- | --- | --- |
| iOS | `build/rc-1.9.1/Texel-iOS.xcarchive` | `ARCHIVE SUCCEEDED`；`com.lingxifox.Texel`、1.9.1 / build 11、arm64、含 dSYMs |
| macOS | `build/rc-1.9.1/TexelMac.xcarchive` | `ARCHIVE SUCCEEDED`；同一 Bundle ID、1.9.1 / build 11、x86_64 + arm64、含 PrivacyInfo 与 dSYMs |

两份归档都是 `CODE_SIGNING_ALLOWED=NO` 的本地产物，不含 distribution 签名、描述文件或可上架 IPA；Mac 归档为 ad-hoc linker-signed，可在本机启动，不能作为上传 App Store Connect 的证据。

### 安装与启动

- iPad 13（iOS 27.2）：Debug 构建安装、启动，两栏首页、额度 5/5、设置 / 保险箱 / 历史 / Pro 整页 sheet 正常。
- macOS（Apple Silicon，macOS 15）：`Texel.app` 启动，窗口 1160×780，侧栏「转换 / 成果保险箱 / 任务历史」，额度 5/5；设置窗口 560×450，四档 Pro 页、试用卡与法务正常。
- iPhone 17（iOS 27.2）：自动化测试与 UI 冒烟使用；本轮没有真机。

## 4. 最终 CI

- GitHub Actions run：[`43246117486`](https://github.com/LingXiFox/LingXiStyle/actions/runs/43246117486)（head `d983ae3`）。
- 该 run 覆盖 Policy and project checks、macOS unit tests、macOS app build and pipeline tests、iOS 18.5 compatibility、iOS 26.x current。
- 首次结果：Policy、macOS unit、macOS app + pipeline、iOS 26.x 通过；iOS 18.5 的 `TutorialUITests.swift:46` 失败，日志显示 first-run tutorial 约 26 秒后才出现，超过 20 秒断言。根因是 `RootView` 先 `await model.onAppear()`（额度 / StoreKit / 保险箱 bootstrap）再 `presentTutorialIfFirstLaunch()`。
- 修复：`RootView` 改为先 `presentTutorialIfFirstLaunch()` 再 `await model.onAppear()`；本机 `LingXiUITests` 6 项（5 通过、1 条 iPad-only 跳过、0 失败）。复跑 run 待推送后确认，不把首次失败写成通过。

## 5. 通过 / 失败 / 跳过数

| 套件 | 环境 | 执行 | 通过 | 跳过 | 失败 |
| --- | --- | ---: | ---: | ---: | ---: |
| `LingXiKitTests` | macOS arm64 | 73 | 73 | 0 | 0 |
| `LingXiPurchaseTests` | iPhone 17 模拟器（iOS 27.2） | 29 | 29 | 0 | 0 |
| `LingXiEngineTests` | macOS arm64 | 5 | 5 | 0 | 0 |
| `StylePortCoreTests` | macOS arm64 | 15 | 13 | 2 | 0 |
| `LingXiIntegrationTests` | iPhone 17 模拟器 | 37 | 37 | 0 | 0 |
| `LingXiUITests` | iPhone 17 模拟器 | 6 | 5 | 1 | 0 |
| `LingXiMacPipelineTests` | macOS arm64 | 3 | 3 | 0 | 0 |
| **合计** |  | **168** | **165** | **3** | **0** |

- UI 的 1 条跳过是 iPad-only 布局用例在 iPhone 上按设计跳过；Core 的 2 条跳过依赖外部 fixture。
- 已知偶发：`LingXiPurchaseTests` 整套首次运行曾出现一次 `StoreKitServiceError(... ErrorType.system(StoreKitInternalError.unknown), environment: XcodeTest)`，单跑与后续整套重跑通过；判断为 StoreKitTest 会话脏状态，不是商品配置或验签缺陷。CI 使用全新模拟器未复现。

## 6. StoreKit 商品、权益与跨设备

| 商品 | ID | 类型 | 本地测试价 | 说明 |
| --- | --- | --- | ---: | --- |
| 永久版 | `com.lingxifox.LingXiStyle.pro` | NonConsumable | $2.99 | 沿用 1.8.1 商品 ID，老用户不重复购买 |
| 24 小时日卡 | `com.lingxifox.LingXiStyle.pro.day` | NonRenewingSubscription | $0.49 | 一次性 24h，不自动续订 |
| 周订阅 | `com.lingxifox.LingXiStyle.pro.weekly` | Auto-Renewable | $0.99 | 1 周 |
| 月订阅 | `com.lingxifox.LingXiStyle.pro.monthly` | Auto-Renewable | $1.99 | 1 个月 |

- 价格只读 `Product.displayPrice`；UI、测试与文档不硬编码币种。
- 权益合成顺序：永久版 > 到期最晚的活跃订阅 > 日卡（Apple 交易时间 + 24h）> 24h 体验；过期、撤销、非 Pro 商品全部忽略。
- 日卡跨设备恢复依赖同一 Apple ID 的 StoreKit 交易历史（`Transaction.all`）；本机 Keychain 只是镜像，不能单独跨设备。设备离线且从未同步到该交易时无法恢复，这是 StoreKit 的边界。
- 订阅支持购买、恢复、管理订阅入口、有效期显示；退款 / 撤销后回到实际权益；有永久版或活跃订阅时不重复推销其他档。
- 24h 体验：每设备一次，Keychain 记录 `claimedAt` 与设备种子；不订阅、不扣费；从确认领取计时；到期回落到实际权益；卸载重装通常不重置，但抹机 / 清空 Keychain 可绕过，不能宣称绝对防刷。
- 价格策略：线上永久版保持 $2.99；191.md 规划的 $7.99 属于改价，本轮未获授权，未修改线上或本地测试价。

## 7. 保险箱、任务与额度

- 保险箱默认保留 7 天，可设 3 / 7 / 14 / 30 天或永久；插入使用 `.staging` + 原子 rename，崩溃不留下半成品；根目录排除 iCloud 备份。
- 成果支持预览、重新保存、导出、删除；重存走独立保存路径，不经过 reserve / commit，不扣额度；Live Photo 同时保留 HEIC 主图与 MOV 配对视频。
- 自动清理跳过仍在执行的任务成果；保留期缩短从修改时刻起重新计时，不会立即清空。
- 任务日志记录时间、张数、模式、状态、结果、保险箱记录、保存资产与额度预留；`recoverInterrupted` 把 running / waitingToSave 标为 interrupted，未确认保存的预留一律释放，幂等。
- 每张只在确认保存后提交一次额度；失败、取消、不兼容、跳过、保存失败不扣；重复保存、导出、保险箱重存、恢复都不会重复扣费。
- 验证：`VaultStoreTests` 8 条、`TaskJournalTests` 7 条、`VaultJournalPipelineTests` 3 条、`VaultJournalIntegrationTests` 3 条；真实 HEIC 管线与真实 PhotoKit 保存回读均通过。
- 未做真机强杀；中断恢复由 journal 状态与自动化覆盖，不能写成真机强杀通过。

## 8. Live Photo 与真实照片

- 真实素材：`Tests/Fixtures/IMG_5296.HEIC`（48MP）与 `Tests/Fixtures/LivePhoto/IMG_5963.HEIC` + `IMG_5963.MOV`（1920×1440、30 fps、53 帧）。
- 仅主帧：输出 MOV 与源 MOV 字节相等；HEIC 通过完整性校验；额度只扣 1。
- 完整处理：输出 MOV 增加 `texturestyle-info` 轨，主视频仍为 53 帧，音频、时间戳与配对保留；额度只扣 1。
- 轨道结构：`testAddsTextureTrackAndReadsItBack` 写回后重读，track handler 为 `meta`、sample 数 53、时间戳与主视频一致、moov `meta` 含 `com.apple.quicktime.texturestyle.`。
- 真实保存：`saveNewLivePhoto` 单事务写入 `.photo` + `.pairedVideo`，回读 `PHAsset.mediaSubtypes` 含 `.photoLive`，无 saveWarning。
- 异常：损坏 MOV 转换失败、额度保持 5；缺失配对 / 非 HEIF / RAW / 已处理素材走 `CompatibilityEvaluator` 的明确诊断。
- 106 帧合成素材用于「超过 90 帧」回归，完整处理成功、帧数 106、额度只扣 1；这是合成回归，不是原生 90+ 帧拍摄。
- 未验证：真机安装、真实相册配对、系统「照片」App 的逐帧动态呈现与音频播放。容器 / 轨道结构正确不等于系统播放一定显示纹理。
- P1 第二代摄影风格 → 第三代纹理 / 颗粒：研究结论为暂不集成，不阻塞发布，依据见 `docs/compatibility/photo-styles-research-1.9.1.md`。

## 9. 验证分类：真机 / 模拟器 / 自动化 / 未验证

| 类别 | 已验证 | 未验证 |
| --- | --- | --- |
| 真机 | 无 | iPhone / iPad / Mac 真机安装、真机 Keychain 共享组、真实相册写入、真实交易 |
| 模拟器 | iPhone 17（iOS 27.2）启动、首页、设置、保险箱、历史、Pro、教程、购买测试、集成测试；iPad 13 竖屏 / 横屏两栏与整页 sheet | iPad 分屏 / 多任务 / 拖放的真实手势；iPad 购买页真实 StoreKit 运行时 |
| 自动化 | 七套 168 项 / 165 通过 / 3 跳过 / 0 失败；iOS / Mac Debug+Release 构建；两份 unsigned archive | 真机强杀、真实订阅续订 / 退款 / 撤销、双真机日卡恢复、Mac GUI 完整转换 |
| macOS 本机 | 启动、窗口 1160×780、设置、四档 Pro 页、额度 5/5；Finder 导入 `IMG_5296.HEIC` 到「1 张待转换」 | GUI 点击转换、App Store 签名上传、Mac App Store 安装 |
| 未验证 |  | iOS 18 / 26 真机与运行时人工走查、App Store Connect 通用购买线上配置、TestFlight |

## 10. App Store Connect 手动配置

以下均为人工步骤，本轮未执行线上变更：

1. 在 App Store Connect 现有 `com.lingxifox.Texel` App 记录中新增 macOS 平台；不要新建 App 记录，不要恢复 `com.lingxifox.Texel.Mac`。
2. 确认四个商品挂在同一 App 下：永久 `...pro`、日卡 `...pro.day`、周 `...pro.weekly`、月 `...pro.monthly`；价格、地区与可售状态按实际授权配置。
3. 上传 Mac 构建前，用同一 Team 的 Mac App Distribution 证书与 profile 签名；当前本地归档未签名，不能直接上传。
4. 在 App Store Connect 开启 Universal Purchase，确认 iOS / iPadOS / macOS 共用同一商品与权益。
5. 配置 macOS 截图（2560×1600 或 2880×1800）、隐私说明、支持 URL、审核备注；截图规格见 `docs/app-store/screenshots-1.9.1.md`。
6. 确认 App 与 Share Extension 的 Keychain Access Group 在签名后都是 `$(AppIdentifierPrefix)com.lingxifox.Texel.shared`；ad-hoc 构建的额度回退行为不能当作线上验证。
7. 提交审核前完成真机交易、订阅续订 / 取消 / 退款、恢复购买与双设备日卡恢复；本轮未提审、未上传。

## 11. 剩余风险

| 风险 | 影响 | 处理建议 |
| --- | --- | --- |
| 无真机验证 | 权限、相册写入、Live Photo 动态呈现、真实交易均可能和模拟器不同 | 提审前完成 iPhone / iPad / Mac 真机矩阵 |
| 无 distribution 签名 | 当前 archive 不能上传或安装到真机 | 用正式证书重签、导出 IPA、上传 TestFlight |
| ASC 未配置 macOS | 通用购买线上不成立 | 按第 10 节人工配置并复核 |
| 日卡跨设备依赖 StoreKit 历史 | 离线新设备可能暂时读不到日卡 | UI 说明需联网恢复；不把 Keychain 当跨设备凭证 |
| 体验防刷非绝对 | 抹机 / 清 Keychain 可再次领取 | 接受为每设备一次的产品边界，不宣称绝对防刷 |
| StoreKitTest 偶发 unknown | 本地整套测试偶发 1 条失败 | 重跑确认；CI 全新模拟器不复现 |
| Mac GUI 未跑完整转换 | 只证明导入到队列与管线测试 | 真机 / 本机人工跑一次导入→转换→导出 |
| 分享扩展 / 快捷指令容器隔离 | 不读主 App 保险箱与历史 | 作为 1.9.1 已知边界记录 |
| Core 2 条 fixture 跳过 | Live Photo 样式写回测试未默认执行 | 提供干净 fixture 后再启用，不伪造通过 |
| 第二代摄影风格未集成 | 部分新素材可能没有第三代纹理效果 | 研究记录归档，后续单独立项 |

## 12. RC 判断

**工程 RC 候选成立，但不具备直接提审条件。**

- 成立的部分：三平台代码与四套构建通过；七套自动化 168 项、0 失败；保险箱、任务恢复、额度幂等、多档 Pro、跨设备日卡、iPad 两栏与 macOS 原生界面均有代码与自动化证据；通用购买的代码侧 Bundle ID、商品 ID、Keychain 组已统一。
- 不成立的部分：没有真机、没有 distribution 签名、没有 App Store Connect macOS 平台与 Universal Purchase 线上配置、没有真实交易 / 订阅 / 退款 / 双设备日卡验证；Mac GUI 只完成导入到队列，未点击转换。
- 建议：冻结 `d983ae3` 作为 RC1 代码基线；先完成真机矩阵与 TestFlight，再按第 10 节配置 ASC；在这些完成前不把本报告当作提审通过或线上可用证明。
