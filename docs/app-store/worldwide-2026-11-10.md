# Texel 中国大陆以外地区配置与搜索素材

2026-11-10 执行。用户在本轮明确批准：App 与 Pro 同步开放全部现有地区、仅排除中国大陆，
保留美国 $2.99 基准和 Apple 自动本地定价，不自动开放未来新增地区；另行批准所展示的
Texel 搜索创意图、原生 ImageIO 放大导出、单张素材的独立审核，以及获批后用于搜索展示。
本轮没有提交 App 版本审核，没有重新构建 IPA，没有修改协议、DSA 身份、税务或银行资料。

## 地区变更已完成并回读

- Apple 当前地区目录 175 个；目标和最终配置均为 174 个（只排除 CHN）。
- App 与 Pro 原来均只有 USA，本轮各新增 173 个，没有移除美国。
- App 与 Pro 的最终地区集合完全相同。
- App 和 Pro 的 availableInNewTerritories 均为 false。
- 美国基准地区 USA、Pro 手工基准价 $2.99 和原有手工价记录前后相同；没有发出价格写请求。
- 自动价格查询返回 174 条，manual=false；App 原有免费价格不变。
- 通过官方 POST /v1/inAppPurchaseAvailabilities 更新 Pro，PATCH /v1/territoryAvailabilities/{id} 更新 App；未使用私有网页接口。
- App 1.7.1 当前 READY_FOR_SALE；Texel Pro APPROVED。这不是一份等待首次 App 审核的新版本。

地区配置成功不等于所有地区已经可下载。最终复查时的 API 状态（仍可能继续传播）：

| 状态 | 已选择地区数量 |
| --- | ---: |
| AVAILABLE | 147 |
| TRADER_STATUS_NOT_PROVIDED | 27 |

欧盟 DSA 在浏览器商务页显示“正在审核”，API 对相关 27 个地区返回 TRADER_STATUS_NOT_PROVIDED。
按用户要求已选入销售范围，不等待或修改该审核。首次回读曾有 26 个地区处于 PROCESSING_TO_AVAILABLE，最终复查均已转为 AVAILABLE；
其他 147 个已选地区均为 AVAILABLE，终端商店缓存仍可能滞后。中国大陆保持 available=false，仍返回 ICP_NUMBER_MISSING / CANNOT_SELL。
重点检查 USA、JPN、HKG、TWN、GBR、BRA 均为 AVAILABLE；DEU、FRA 为交易者验证限制。
没有为巴西或其他地区填写任何新的税务资料。

## 现有四语言资料已核对

最终只读诊断确认 en-US / zh-Hans / zh-Hant / ja 均有名称、副标题、描述、推广文字、关键词、
支持网址、营销网址和隐私政策网址；文案及审核备注与当前 origin/main 的实际 listing.md 完全一致。
审核联系人四个必需字段均已填写，仅记录存在性，不在交付中显示联系人内容。
四语言各 6 张截图，24 张图片均 APPROVED、对应 placement 均 ACTIVE。
首发版本的 whatsNew 按既有客户端规则省略，不是未完成的必填项。

## 搜索图已准备并提交独立素材审核

App Store Connect 英语（美国）页面确实显示“0/1 个搜索结果素材”。
四语言共 24 张普通截图都已 APPROVED、placement ACTIVE；缺少的是可选创意素材，
不是缺失普通截图。Apple 在没有搜索创意时会回退使用截图/预览，实际搜索样式仍由商店决定。

采用用户确认的深蓝色品牌设计，文字只有 Texel / Texture & Grain，使用本仓库实际 App 图标作参考。
图片通过内置 imagegen 工具生成，原稿 1536×1024；用户明确批准 ImageIO 放大为 3072×2048，
最终 PNG 实际 3:2、8-bit RGB、无透明通道，CRC 和像素数据校验通过。
它是品牌创意插画，不作为真实 App 截图或原生高分辨率生成结果。

- 最终图片：AppStoreScreenshots/Creative/texel-search-en-v1-3072x2048.png。
- 完整提示词和处理记录：AppStoreScreenshots/Creative/texel-search-en-v1-prompt.txt。
- SHA-256：2ff10e68757c44074ba18c4205ada14a0c7cb15d2ce881fcc3e9d32c6d4a2b51.
- Apple 图片 ID：30400019-73f4-8892-8022-18f26d5f21f9，类别 CREATIVE_ASSETS。
- Apple 真实处理规格和尺寸已回读验证；独立审核 d66265a6-b1a1-4e11-bdc4-fb9d9e7b2d89
  于 2026-11-10T05:11:44.108Z 提交，仅含这一张图片。
- 当前 WAITING_FOR_REVIEW，不宣称已经在美区搜索结果展示。
- 已启动有期限的获批后绑定任务：每分钟查询、最多 24 小时，只有 APPROVED 后才为
  en-US / zh-Hans / zh-Hant / ja 的已上架 1.7.1 添加搜索 placement。
- 遇到拒绝、失败、版本不再上架或已有不同搜索图时停止；不删除、覆盖其他素材。

发布客户端在提交前再次读取整个审核草稿：必须只有目标图片，拒绝包含 App 版本、内购、其他素材的混合草稿。
单张素材的授权不改变默认禁止 App 版本提交审核/发布的保护。
后台任务和最终结果写入本地 .tmp/appstoreconnect/worldwide-20261110/creative-state.json。
如果审批超过 24 小时，可在获得最新状态后按 api-client.md 的 creative 命令安全续跑，不会重复创建资产。

## 验证与交付

32 项离线测试通过；包括 CHN 排除、完整地区预览、未来地区开关、篡改预览拒绝、图片限定审核和混合草稿拒绝；已上架版本重复 prepare 不会创建新审核草稿。
Trivy secret 扫描 0 项。未修改 App 业务代码，未新增依赖。原有工作区三处用户改动保持不变。
复用命令见 [api-client.md](api-client.md)。执行预览、地区进度、价格和最终回读均留在本地 .tmp/。

仍待 Apple：DSA 验证和搜索素材审核/展示传播。
未逐地区实测终端下载、真实内购交易或公众搜索结果；现有已上架版本无需仅因本次扩区重新打包。

官方依据：
- [管理 App 销售地区](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)
- [管理素材及已上线版本的创意图](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets)
- [创意素材规格](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
