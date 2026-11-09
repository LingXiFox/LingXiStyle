# Texel 1.7.1 官方 API 执行记录

日期：2026-11-09。此报告区分实际 API 结果、离线测试与仍未验证的部分。

## 连通性与当前状态

- 首次请求仅执行 `GET /v1/apps`，成功返回目标账户的 Texel。
- 名称：Texel - Texture & Grain。
- Bundle ID：`com.lingxifox.Texel`；Apple App ID：`6832474258`；主语言：en-US。
- 唯一 iOS 商店版本：1.7.1，状态 `PREPARE_FOR_SUBMISSION`。
- 目标版本的 `build` 关系实际返回 `data: null`；仍需上传并选择要审核的构建。
- 当前 `releaseType` 为 `AFTER_APPROVAL`；没有提交审核，也没有修改发布方式。
- `GET /v1/apps/6832474258/appAvailabilityV2` 返回 404，尚未返回可用地区配置。
  因而不能确认已经限定美国首发；本轮没有创建或修改销售地区。

认证使用本地 P-256 私钥、ES256 JWT、600 秒有效期；认证文件均在仓库外。
私钥、JWT、真实联系人和上传 URL 未进入 Git、预览或执行日志。

## 409 诊断及修复

版本本地化、应用信息本地化均已有四个资源，审核信息也已有一个资源。
实际变更全部使用 PATCH；没有反复 POST 或创建重复本地化/审核资源。

审核备注第一次 PATCH 返回 HTTP 409，原始错误如下：

| code | detail | source.pointer |
| --- | --- | --- |
| ENTITY_ERROR.ATTRIBUTE.REQUIRED | You must provide a value for the attribute 'contactFirstName' with this request | /data/attributes/contactFirstName |
| ENTITY_ERROR.ATTRIBUTE.REQUIRED | You must provide a value for the attribute 'contactLastName' with this request | /data/attributes/contactLastName |
| ENTITY_ERROR.ATTRIBUTE.REQUIRED | You must provide a value for the attribute 'contactEmail' with this request | /data/attributes/contactEmail |
| ENTITY_ERROR.ATTRIBUTE.REQUIRED | You must provide a value for the attribute 'contactPhone' with this request | /data/attributes/contactPhone |
| ENTITY_ERROR.ATTRIBUTE.INVALID | The phone number must be in a valid format. Preface the phone number with ‘+’ followed by the country code (for example, +44 844 209 0611) | /data/attributes/contactPhone |

实际只读检查确认当时四个联系人字段均为空。用户在仓库外提供真实联系人后，
客户端在进程内合入 PATCH，审核备注和四字段全部回读一致，结果 VERIFIED。
不是因为审核资源不存在，也不需要删除重建。

版本本地化 PATCH 本轮成功，未复现 409。浏览器原请求体与错误体没有提供，
所以不能把历史版本本地化 409 断定为重复创建或任何其他单一原因。
保存失败的实际结果已经通过官方 API 更新解决；浏览器原保存动作未重新操作。

## 已完成的四语言资料

文案来自 GitHub `LingXiFox/LingXiStyle` main 的 commit
`03c79a59d289eb78a2f7881879dd4b2a7fe892c6`，路径 `docs/app-store/listing.md`。
客户端记录源文本 SHA-256：`2b94360e0b2e9b7c9f45f1c6400325a8b571cb923ff0fbc75e02e6b7c1763546`。
没有使用本地未提交文案中额外的 `$$  $$`；没有改写用户的该项工作区改动。

| Locale | Name | 结果 |
| --- | --- | --- |
| en-US | Texel - Texture & Grain | 英文版本文案原已一致；补全副标题与隐私链接 |
| zh-Hans | 纹粒 Texel - 纹理与颗粒 | 名称、副标题、隐私链接与版本文案 PATCH 后回读一致 |
| zh-Hant | Texel - 真實紋理與顆粒 | 名称、副标题、隐私链接与版本文案 PATCH 后回读一致 |
| ja | Texel - フィルムの質感 | 名称、副标题、隐私链接与版本文案 PATCH 后回读一致 |

四语言均有描述、推广文字、关键词、支持 URL、营销 URL；共享审核备注取自仓库英文原文，
无需登录和演示账户。首发版本未填写 What's New，仓库原有更新说明保留。
共 7 个本地化资源更新成功，另 1 个审核信息资源在补齐联系人后更新成功。
最终重新生成文案预览，待修改项为 0，验证重复运行不会继续改写。

使用用户指定的正式链接：

- 隐私：`https://apps.lingxifox.cn/texel/privacy/`
- 支持：`https://apps.lingxifox.cn/texel/support/`
- 营销：`https://apps.lingxifox.cn/texel/`

三条 URL 的自动化 HTTP 请求均返回 403，网页搜索工具也未能读取。
这是该访问方式的实际结果，不等于已经证明普通浏览器无法访问；本轮未修改网站或 WAF。
发布前仍需检查 Apple 审核环境能够公开访问这些页面，及页面没有占位符。

## 截图

官方实时 `appAssetLibraryRefData` 返回：5 项 feature、37 个 placement group、
84 项 image spec、15 项 video spec、8 种 placement type、20 个 display class。
使用现行 App Asset Library 与 placement 机制。

本地两套图片均为真实 RGB PNG，无 alpha：

- `AppStoreScreenshots/` 四语言各六张，1320×2868；本轮未上传这套原始大屏素材。
- `AppStoreScreenshots/ASC/` 四语言各六张，1206×2622；苹果资产库已有同名、同字节数、
  同 spec 的唯一匹配项，因此复用已有资产，没有重复上传。

| Locale | 数量 | Apple 实际尺寸 | Apple group | 资产状态 | Placement 状态 |
| --- | ---: | --- | --- | --- | --- |
| en-US | 6 | 1206×2622 | IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE | PREPARE_FOR_SUBMISSION | ACTIVE |
| zh-Hans | 6 | 1206×2622 | IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE | PREPARE_FOR_SUBMISSION | ACTIVE |
| zh-Hant | 6 | 1206×2622 | IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE | PREPARE_FOR_SUBMISSION | ACTIVE |
| ja | 6 | 1206×2622 | IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE | PREPARE_FOR_SUBMISSION | ACTIVE |

24 张均通过本地 PNG 完整性/颜色/尺寸校验与苹果处理状态回读；各语言顺序为
Home、Selection、Processing、Result、Quota、Settings，已按真实 placement 顺序验证。
1206×2622 对应苹果当前要求的 Dynamic Island medium display；没有将该尺寸冒充大屏截图。
远端旧资产不提供 source checksum，复用依据为文件名、字节数和 spec 唯一匹配，
没有声称取得远端原始字节 SHA-256。

实际新增上传 0 张；保留并验证已上传 24 张。新的上传、预约恢复和超时处理经过离线测试，
本轮没有为了测试再创建一份真实截图，也没有删除现有资产。

## 内购

`GET /v1/apps/6832474258/inAppPurchasesV2` 实际返回空列表，目标商品
`com.lingxifox.LingXiStyle.pro` 尚不存在。已在本地文案预览中生成四语言创建方案：

| Locale | Name | Description |
| --- | --- | --- |
| en-US | Texel Pro | One-time purchase. Unlimited photos. |
| zh-Hans | 纹粒 Pro | 一次购买，永久不限张数。 |
| zh-Hant | Texel Pro | 一次購買，永久不限張數。 |
| ja | Texel Pro | 一度の購入で、写真の枚数が無制限に。 |

类型应为 `NON_CONSUMABLE`；未创建任何商品。美国目标价 $2.99 只是用户目标，
尚未设置价格或销售地区。现代商品创建端点为官方 `/v2/inAppPurchases`，超出本轮 v1 限定，
可由用户在 App Store Connect 创建，或下一轮明确扩大官方 API 版本范围后再处理。
仍需商品审核截图、实际价格/销售地区确认，以及真实 StoreKit 商品加载与交易验证。

## 验收证据和边界

- 19 项离线回归测试全部通过；包括真实 ES256 验签、本地联系人不落日志、PNG 校验、
  重跑不重复写入，以及恢复现有上传预约。
- `xcodegen generate` 成功，生成的 Xcode project 无变化；未修改 App、Kit、Engine 或转换管线。
- 对 tools 目录执行 Trivy secret/vuln 扫描，中/高/严重级别 findings 为空。
  该结果不代表 Trivy 已识别 script lock 的全部依赖；依赖实际版本由 uv lock 固定。
- 本地预览、原值与执行证据保存在忽略的 `.tmp/appstoreconnect/`，文件权限 0600；
  保留至用户验收，不提交公开仓库。
- 没有执行 App 审核提交、正式发布、价格/销售地区修改、资源删除、证书/密钥变更或财税操作。
- 没有为本任务启动模拟器、服务或持续后台进程；App 二进制与真机流程未重测。

工具用法与 Apple 官方文档入口见 [api-client.md](api-client.md)。
