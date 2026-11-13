# Texel 1.9.1 App Store Connect 准备记录

后续更新：主人已授权中国大陆销售，四档商品从 174 个地区补为包含 CHN 的 175 个地区。原准备过程的快照保留，最新结果见 [大陆销售记录](mainland-sales-2026-11-13.md)。

2026-11-13：按主人授权上传签名构建、配置四档商品及价格、更新四语言资料与补充 iPad / iPhone Duo 截图。**没有提交 App、内购、订阅或截图审核，也没有发布版本。**

## 签名构建

- 来源：已通过 CI 的 main `2b56df0ded48fe74074c51bc68003dd9e31cb356`；GitHub Actions [43400842007](https://github.com/LingXiFox/LingXiStyle/actions/runs/43400842007)。
- App `com.lingxifox.Texel` 与分享扩展 `com.lingxifox.Texel.Share` 均为 1.9.1（11），SDK `iphoneos27.2`。
- 复用有效 Apple Distribution 身份和 App Store profiles；校验归档的签名、Bundle ID、版本、共享 Keychain entitlement 与 Release 未带本地 StoreKit 配置。
- Xcode 正式上传成功；Apple 处理状态 `VALID`。build ID：`a7957ffd-b851-474a-b9e8-5158097a1b39`。
- 已关联现有 iOS 1.9.1 草稿 `4de9bf0f-d2c4-42e2-8b0e-c199928adda6`，保持 `PREPARE_FOR_SUBMISSION`。
- 签名归档与脱敏操作证据保存在本地 `build/asc-1.9.1-20261113/`；不提交签名资产或凭据到仓库。

## 商品与价格

价格来自主人的明确确认，均为美国基准价；其他地区使用 Apple 返回的本地价格点。没有将本地 StoreKit 测试价格作为正式定价依据。

| 方案 | Product ID 后缀 | ASC ID | 美国基准价 | 类型 |
| --- | --- | --- | --- | --- |
| 日卡 | `.pro.day` | 6834355846 | $0.49 | 非续期订阅，App 根据已验证交易日期计算 24 小时 |
| 周 | `.pro.weekly` | 6834355883 | $0.99 | 自动续期，ONE_WEEK |
| 月 | `.pro.monthly` | 6834356027 | $1.99 | 自动续期，ONE_MONTH |
| 永久 | `.pro` | 6832499022 | $7.99 | 非消耗型；复用现有商品 |

完整前缀为 `com.lingxifox.LingXiStyle`。新建订阅组 `22575494`（Texel Pro）；周、月权益相同，均为组内级别 1。未启用 StoreKit introductory offer；应用内每设备一次 24 小时体验保持独立，不自动扣费。

- 三个新商品的可售范围与原永久商品一致：174 个当前地区，排除 CHN，未来地区开关关闭；未修改 App 本身销售范围。
- 周、月 `UPFRONT` 计划各 174 个地区价格全部回读匹配 Apple equalization；日卡和永久使用 USA 基准自动地区价格表。
- 订阅组与三个新商品均补齐 en-US、zh-Hans、zh-Hant、ja 本地化，采用官方 4.6 schema 的独立元数据版本。
- 三个新商品的审核截图均为真实 Pro 页面，交付状态 `COMPLETE`；原永久商品审核截图保留。
- 真实 StoreKit 在截图中返回永久 US$7.99；尚未返回的新商品价格保留实际 UI 占位，没有手绘价格或模拟已购买状态。

### 状态差异

网页订阅组列表显示周、月均为「准备提交」，月订阅详情也显示「准备提交」；元数据版本 API 状态均为 `PREPARE_FOR_SUBMISSION`。旧 `subscriptions.state` 字段仍返回 `MISSING_METADATA`，日卡为 `READY_TO_SUBMIT`。保留此差异，不将它解释为已审核通过，也不为改变状态而触发提交。此轮没有尝试提交验证。

首次订阅价格请求在尚未配置计划可售地区时返回 409，流程立即停止；补齐并回读 `subscriptionPlanAvailabilities` 后再创建尚未写入的地区价格，没有盲目重复 POST。

## 商店资料与截图

四语言描述、推广文字、1.9.1 更新说明以及审核备注已按四档商品更新，并补充 Apple 标准 EULA 链接。保留原名称、关键词、URL 与联系人。

本轮截图按主人批准的六页：主页、设置、成果保险箱、任务历史、Pro、教程。使用独立空模拟器、真实 App 页面，无私人照片、虚构任务或伪造进度。四语言通过启动参数切换，不修改主人的应用语言偏好。

48 张均已上传，并逐张回读验证真实分辨率、spec、图片引用及页面顺序；四语言每个设备组各 6 张，所有 placement 为 `ACTIVE`。没有删除或替换原普通 iPhone 图片。

| 设备 | 原生尺寸 | ASC 截图组 | 数量 |
| --- | --- | --- | ---: |
| iPad 13 英寸 | 2064 × 2752 | IPAD_13_PROFILE | 4 × 6 = 24 |
| iPhone Duo 外屏 | 1398 × 2034 | IPHONE_DUO_PROFILE | 4 × 6 = 24 |

截图原件位于本地 `AppStoreScreenshots/1.9.1/ipad/` 与 `duo/`，四语言子目录为 `en`、`zh-Hans`、`zh-Hant`、`ja`。未补拍 Duo 内屏。最终证据为 `build/asc-1.9.1-20261113/asc/screenshots-final-verified.json`；同次回读确认 build 11 仍为 `VALID`、1.9.1 仍为未提交草稿。

## 验证与范围

- ASC 客户端 34 项离线测试通过，覆盖新订阅写入开关、禁止提交、实际价格快照及 `COMPLETE` 截图状态续传；未新增依赖。Trivy secret 扫描未发现凭据。
- iPad 与 Duo 最终捕获测试均为 1 通过、0 失败、0 跳过；共导出 48 张 RGB PNG，拷贝后字节一致。
- 捕获脚本为临时 XCUITest，不提交到仓库。初次 iPad 历史返回、Duo 外屏标识与懒加载滚动导致捕获脚本失败，均按真实页面入口修正；这些失败不能算作产品流程已通过。
- 未执行真实购买、续订、退款或跨设备权益测试。
- 本轮未添加 macOS 商店平台、上传 Mac 构建或补拍 Mac 截图；线上通用购买仍未验证。

## 资源清理

临时捕获代码已还原；三个本轮专用模拟器、两份 DerivedData 与临时 xcresult / 附件目录已删除。签名归档、截图原件、测试摘要、失败捕获记录和脱敏操作证据保留；修改前快照保留至主人验收。未删除用户已有模拟器或修改私人相册。
