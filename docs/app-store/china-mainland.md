# Texel 1.7.1 — 中国大陆 App 备案与合规清单

本文件是发布准备清单，**不是法律意见**，也不表示任何备案、审核或上架已经完成。
中国大陆的备案与商店要求由工信部、省级通信管理局、Apple 及实际运营主体决定；提交前
必须由主体负责人或合规顾问按最新规定确认。

## 1. 先分清两个“备案”

| 项目 | App 备案 | ICP 备案 |
| --- | --- | --- |
| 对象 | 在境内提供服务的 App | 在境内提供服务的网站 / 域名 |
| 主管 | 工信部及省级通信管理局 | 工信部及省级通信管理局 |
| 与 Texel 的关系 | 在中国大陆 App Store 分发通常需要 App 备案号 | 只有隐私 / 支持页面使用境内服务器和域名时才涉及 |
| 本仓库现状 | **没有备案号**，使用 `<APP_RECORD_NUMBER>` 占位 | **没有 ICP 号**，使用 `<ICP_FILING_NUMBER>` 占位 |
| 能否用 GitHub Pages 规避 | 不能替代 App 备案 | 境外托管通常不办 ICP，但境内访问稳定性与商店审核可访问性需自测 |

> 不要把 App 备案号、ICP 备案号、App Store Connect 的“App 备案”字段混为一谈；也不要在
> 未取得号码时填写任何看似真实的数字。

## 2. 当前产品的合规事实

以下描述来自仓库代码与文档，填写备案/审核材料时应保持一致：

- App 名称：简体中文「纹粒」，其他语言「Texel」；Bundle ID `com.lingxifox.LingXiStyle`；
  版本 1.7.1（build 9）。
- 功能：读取用户选择的 iPhone 16 / 17 HEIC 原片，在本机追加纹理与颗粒，另存为相册新照片。
- 不覆盖原图、不转码、不上传照片；开发者不运营服务器。
- 免费额度：每天 5 张，按设备本地自然日重置；只有成功保存或导出才扣减。
- Pro：一次性非消耗型内购，Product ID `com.lingxifox.LingXiStyle.pro`；非订阅，支持恢复购买。
- 权限：PhotoKit 读取（仅用户选择时）与“添加到照片”（保存时）；没有相机、麦克风、定位、
  通讯录、蓝牙等权限。
- 无账号、无 UGC、无社交、无广告、无新闻、无直播、无游戏、无地图、无金融、无医疗、
  无生成式 AI 功能。
- 无第三方分析 / 广告 / 崩溃 / 社交 SDK；无开发者服务器；无跨境数据传输。
- 支持简体中文、繁体中文、English、日本語；商店文案见 `docs/app-store/listing.md`。

## 3. App 备案材料清单

具体表单与附件以备案系统为准。通常需要主体、App、技术、内容四类材料：

### 3.1 主体材料

- [ ] 营业执照或主体登记证件（真实、在有效期内）。
- [ ] 法定代表人 / 负责人身份证明与联系方式。
- [ ] 备案负责人、安全负责人及应急联系人（姓名、手机、邮箱）。
- [ ] 主体授权书（如由代办人或非法定代表人提交）。
- [ ] 主体实名核验材料（按系统要求）。

> 仓库中没有法律实体名称、地址、负责人或联系方式。使用 `<LEGAL_ENTITY_NAME>`、
> `<LEGAL_ADDRESS>`、`<REVIEW_CONTACT_*>` 占位，**不得编造**。

### 3.2 App 材料

- [ ] App 名称：纹粒 / Texel（与商店名称、安装包显示名称一致）。
- [ ] Bundle ID：`com.lingxifox.LingXiStyle`。
- [ ] 版本号：1.7.1；Build：9。
- [ ] 安装包签名信息（证书、签名指纹等，按备案系统要求提供）。
- [ ] App 图标、截图、功能简介与类目（Photo & Video）。
- [ ] App 下载 / 分发渠道：Apple App Store（中国大陆区）。
- [ ] App 备案号：取得后填写 `<APP_RECORD_NUMBER>`；未取得前保持空白。
- [ ] 如备案系统要求域名：填写隐私 / 支持页面的实际域名；没有境内域名则按系统说明处理。

### 3.3 技术与安全材料

- [ ] 服务端情况说明：**本 App 无开发者服务器**；照片仅在本机处理。
- [ ] 数据收集说明：开发者不收集个人信息；App Store 隐私问卷为 Data Not Collected。
- [ ] 权限说明：相册读取 / 添加的用途、触发时机、拒绝后的降级路径。
- [ ] 安全措施：系统沙盒、PhotoKit、Keychain、StoreKit 2 交易验证；无明文传输。
- [ ] 日志与诊断：诊断信息仅本地/用户主动导出；不上传开发者服务器。
- [ ] 第三方组件：仅 Apple 系统框架；如未来加入 SDK，必须更新清单与隐私政策。

### 3.4 内容与资质判断

- [ ] 不需要网络文化经营许可证、信息网络传播视听节目许可证、网络出版服务许可证、
      互联网新闻信息服务许可证等（当前无对应功能）。
- [ ] 不涉及游戏版号、直播、短视频、论坛、社交、UGC 内容审核。
- [ ] 不涉及地图测绘、金融支付、征信、医疗健康、教育培训等前置审批。
- [ ] 如未来增加账号、云端处理、社区、广告或 AI 生成，必须重新评估备案与资质。

## 4. 公开页面与域名

中国大陆 App Store 的隐私政策与支持 URL 必须可公开访问、无需登录，且内容与 App 行为一致。

- 隐私政策：`docs/privacy/index.html` → 部署为 `<PUBLIC_BASE_URL>/privacy/`。
- 技术支持：`docs/support/index.html` → 部署为 `<PUBLIC_BASE_URL>/support/`。
- 营销首页（可选）：`docs/index.html` → `<PUBLIC_BASE_URL>/`。
- 四语言页面已包含 zh-Hans / zh-Hant / en / ja；中国大陆审核至少确保简体中文可读。
- 页面不得包含虚构的备案号、公司名、邮箱、审核状态或“App Store 推荐”等表述。
- 若使用 GitHub Pages：无需 ICP 备案，但境内访问可能不稳定；提交前用境内网络实测，
  必要时改用境内合规静态托管并办理 ICP 备案。
- 若使用境内域名/服务器：先完成 ICP 备案，再把 `<ICP_FILING_NUMBER>` 填入商店或页面要求的位置。
- 隐私政策中的联系邮箱 `<PRIVACY_EMAIL>`、支持邮箱 `<SUPPORT_EMAIL>` 必须是真实可达的；
  仓库当前没有，禁止编造。

## 5. App 内备案号展示

监管与商店可能要求 App 内可查看备案信息。当前版本**没有**备案号展示入口；这是取得真实
备案号后的人工代码待办，不要在号码未取得前添加假号码。

建议实现（取得号码后）：

- 在设置页“关于”区域增加“备案号”一行，显示 `<APP_RECORD_NUMBER>`。
- 如适用，同时展示 ICP 备案号与查询链接（`https://beian.miit.gov.cn/`）。
- 文案走 String Catalog 四语言；号码本身不翻译。
- 不把备案号写死到截图、商店文案或测试 fixture 中。
- 变更后重新构建、跑设置页冒烟测试，并更新 `TEST_REPORT.md`。

## 6. 权限与隐私合规

- [ ] `NSPhotoLibraryUsageDescription` 与 `NSPhotoLibraryAddUsageDescription` 均为中文可读，
      说明“读取所选 HEIC 原片”和“另存为新照片”，不写“需要全部相册权限”。
- [ ] 启动时不请求相册权限；用户选片后再请求读取，保存前才请求添加。
- [ ] 拒绝权限后提供系统设置与文件导入两条恢复路径；不要用假弹窗或循环请求。
- [ ] 隐私政策披露：本机处理、临时文件、Keychain 额度、StoreKit、iCloud 由 Apple 处理、
      无分析/广告/跟踪、无账号、无出售。
- [ ] App Store 隐私问卷与代码一致；当前选择 Data Not Collected，提交前逐项复核。
- [x] App target 已提供 `App/Resources/PrivacyInfo.xcprivacy`：`UserDefaults` 使用
      required reason `CA92.1`，`NSPrivacyTracking` 为 false，未声明收集数据类型。
- [ ] 如 Share Extension、Shortcuts 或未来 SDK 使用 required reason API，需为其 bundle
      补充独立隐私清单，并在 App Store Connect 复核。
- [ ] 不申请与功能无关的权限；不集成 IDFA / ATT，除非未来确有广告与跟踪。

## 7. 内购与支付

- [ ] Pro 只通过 Apple In-App Purchase 销售；Product ID `com.lingxifox.LingXiStyle.pro`。
- [ ] 不提供外部支付链接、二维码、跳转网页购买或“联系开发者购买”。
- [ ] 价格只读 `Product.displayPrice`；商店文案、截图、审核备注不得硬编码币种金额。
- [ ] 一次性非消耗型；支持恢复购买；退款/撤销后回到免费额度。
- [ ] 审核备注说明 Pro 不是订阅、无账号、无开发者服务器。
- [ ] 中国大陆的 Apple IAP 由 Apple 处理；开发者不自行收取人民币款项。

## 8. 内容、年龄分级与商店信息

- [ ] 年龄分级按 App Store Connect 问卷如实填写；当前预期 4+（无暴力、色情、赌博、
      恐怖、酒精烟草、用户生成内容、广告）。
- [ ] 主要分类 Photo & Video；不为了排名堆砌无关分类。
- [ ] 截图与文案不出现虚构评分、媒体引用、奖项、折扣倒计时或“官方推荐”。
- [ ] 中国大陆商店截图优先简体中文；如使用四语言截图，确保每张都来自真实 App。
- [ ] 商店名称、副标题、描述、关键词与 `docs/app-store/listing.md` 一致。
- [ ] 不宣称“已备案”“已通过审核”“App Store 已上架”，直到真实发生。

## 9. 数据出境与个人信息保护

- [ ] 开发者不运营服务器，不向境外提供开发者收集的个人信息。
- [ ] 照片在本机处理；iCloud 原片下载、App Store 购买与恢复由 Apple 按其条款处理。
- [ ] 如未来增加云端处理、账号、分析或客服系统，必须重新评估 PIPL / 数据出境 /
      个人信息保护影响评估，并更新隐私政策与 App Store 隐私问卷。
- [ ] 用户权利请求渠道使用真实 `<PRIVACY_EMAIL>`；无法处理时不得虚构响应承诺。
- [ ] 不把“无服务器”写成“绝对没有任何数据处理”：Apple 系统服务、相册与购买仍会按
      Apple 的规则处理数据，隐私政策已分别说明。

## 10. App Store Connect 填写建议

| 字段 | 建议值 / 状态 |
| --- | --- |
| China mainland availability | 取得 App 备案号并完成可访问性检查后再勾选 |
| App 备案号 | `<APP_RECORD_NUMBER>`（未取得前留空） |
| ICP 备案号 | 仅在有境内网站备案时填写 `<ICP_FILING_NUMBER>`；没有就不要编造 |
| 隐私政策 URL | `<PUBLIC_BASE_URL>/privacy/` |
| 支持 URL | `<PUBLIC_BASE_URL>/support/` |
| 版权 | `© 2026 LingXiFox`（如实际主体不同，按主体修改） |
| 审核备注 | 说明无账号、无服务器、相册权限用途、Pro 为一次性内购 |
| 审核联系人 | `<REVIEW_CONTACT_NAME>` / `<REVIEW_CONTACT_EMAIL>` / `<REVIEW_CONTACT_PHONE>` |

> 字段名称与是否必填会随 Apple 与监管要求变化；以 App Store Connect 提交页面的实时提示为准。

## 11. 建议执行顺序

1. 确定实际运营主体、法律实体名称、地址、隐私邮箱、支持邮箱。
2. 部署隐私 / 支持 / 首页，替换 `<PUBLIC_BASE_URL>` 与联系邮箱，境内网络实测。
3. 按主体所在地通信管理局 / 备案系统提交 App 备案，取得真实备案号。
4. 如使用境内域名，完成 ICP 备案并取得 ICP 号。
5. 在 App Store Connect 填写真实备案信息；未取得前不要提交中国大陆区。
6. 取得号码后，在设置页增加备案号展示（人工代码变更），重新构建并验证。
7. 完成 App Privacy、年龄分级、截图、审核备注与内购审核材料。
8. 提交 App Review；不要在本轮执行真实提交或真实购买。

## 12. 人工待办（不可由仓库自动完成）

- [ ] `<LEGAL_ENTITY_NAME>`：实际法律实体 / 备案主体名称。
- [ ] `<LEGAL_ADDRESS>`：主体注册地址或通信地址。
- [ ] `<PRIVACY_EMAIL>`：隐私请求邮箱。
- [ ] `<SUPPORT_EMAIL>`：技术支持邮箱。
- [ ] `<PUBLIC_BASE_URL>`：已部署、可公开访问的 HTTPS 根地址。
- [ ] `<APP_RECORD_NUMBER>`：工信部 App 备案号（取得后填写）。
- [ ] `<ICP_FILING_NUMBER>`：如适用，网站 ICP 备案号。
- [ ] `<REVIEW_CONTACT_NAME>` / `<REVIEW_CONTACT_EMAIL>` / `<REVIEW_CONTACT_PHONE>`：
      App Review 联系人。
- [x] App target 的 `PrivacyInfo.xcprivacy` 已提供（`UserDefaults` / `CA92.1`）。
- [ ] 确认 Share Extension 或未来 SDK 是否需要独立 `PrivacyInfo.xcprivacy`。
- [ ] 取得备案号后增加 App 内展示入口，并更新四语言文案与测试。
- [ ] 用真实主体与境内网络复核本清单；本文件不替代法律意见。

## 13. 参考

- 工信部 ICP/IP 地址/域名信息备案管理系统：`https://beian.miit.gov.cn/`
- Apple App Store Connect 帮助与提交页面中的 China mainland / 合规字段（以实时页面为准）
- 仓库内：`docs/app-store/listing.md`、`docs/privacy/index.html`、`docs/support/index.html`、
  `AppStoreRelease.md`、`README.md`

> 最后更新：2026-11-07。所有备案号、主体信息与审核状态均为未完成占位；不得把本清单当作
> 已备案或已通过的证据。
