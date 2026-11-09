# Texel 1.7.1 正式签名与可提审状态

2026-11-09 完成。使用官方 App Store Connect API 和 Apple 本机工具。
App 与 Texel Pro 已加入同一份未提交审核草稿，两个条目均为 `READY_FOR_REVIEW`。
没有提交 App Review，没有正式发布，没有在本轮变更价格、地区或商业配置。

## 构建与签名

| 项目 | 已验证结果 |
| --- | --- |
| App / Apple ID | Texel - Texture & Grain / 6832474258 |
| App Bundle ID | com.lingxifox.Texel |
| Share Bundle ID | com.lingxifox.Texel.Share |
| 版本 / 构建号 | 1.7.1 / 9，两个 bundle 一致 |
| Xcode / SDK | 稳定版 27.2（27B52）/ iPhoneOS 27.2 |
| Team | R9UJHHAZQ4 |
| 分发证书 | Apple Distribution: Zhihan Zhu；NT9D2XJ3Q2 |
| 证书有效期 | 2027-11-09 10:05:24 UTC |
| App 描述文件 | Texel App Store com.lingxifox.Texel NT9D2XJ3Q2 |
| Share 描述文件 | Texel App Store com.lingxifox.Texel.Share NT9D2XJ3Q2 |
| 描述文件有效期 | 两份均至 2027-11-09 10:05:24 UTC；IOS_APP_STORE |
| Archive | 本地 .tmp/appstoreconnect/manual-release-27.2-r3/Texel.xcarchive |
| 上传 | xcodebuild -exportArchive 返回 EXPORT SUCCEEDED / Upload succeeded |
| Apple 构建 ID | b05e844e-a74c-4578-8d48-6d16c5085f2e |
| Apple 处理状态 | VALID，已关联到 1.7.1 |

私钥、证书、描述文件和本地 xcconfig 均在用户配置目录/Keychain，不进入 Git。
Release 手动分发签名，Debug 自动开发签名。两个 bundle 的共享 Keychain entitlement
均为 `R9UJHHAZQ4.com.lingxifox.Texel.shared`，get-task-allow 为 false。
Archive 严格签名验证通过，不包含 Configuration.storekit。

首次 Apple 上传校验准确报出：扩展包含不允许的 Frameworks、嵌套 bundle，且四个 framework
与主 App 出现 Bundle ID 冲突。已修正 XcodeGen：只在主 App 嵌入四个 framework，
Share Extension 通过 `@executable_path/../../Frameworks` 加载同一套二进制。
重新归档后上传成功，构建号仍为 9。

## 商店资料与 409

- API 连通、App 名称、Bundle ID、Apple ID 均核对一致。
- GitHub 已提交来源：72ee6b8a74ed768c4dc5b0c8ccae36f1acba4354 的 docs/app-store/listing.md。
- listing SHA-256：2b94360e0b2e9b7c9f45f1c6400325a8b571cb923ff0fbc75e02e6b7c1763546。
- 四语言 en-US、zh-Hans、zh-Hant、ja 的名称/副标题、描述、推广文字、关键词、支持/营销 URL、隐私政策与版本资料已填写；重新预览为 0 项变更。
- 审核联系人与备注已保存；日志和预览仅保留联系人字段是否存在，不保留个人内容。
- 分类 PHOTO_AND_VIDEO，年龄分级 FOUR_PLUS，无第三方内容权利声明已填写。
- 隐私标签“不收集数据”由用户在浏览器最终确认发布；该项没有公开 API，本轮没有重复操作。

实际复现的审核信息 409 包括缺少四个联系人字段及电话号码格式不合法。合入本地真实联系人后
PATCH 成功并 GET 回读。版本本地化资源原本已存在，使用 PATCH 后均保存成功；
没有浏览器原始错误体，不能把其 409 的具体原因断言为重复创建。当前保存问题已解除。

## 截图与内购

| 资源 | 已验证状态 |
| --- | --- |
| App 商店截图 | 四语言各 6 张，共 24 张；1206×2622 RGB PNG；处理完成为 PREPARE_FOR_SUBMISSION，placement ACTIVE |
| Pro 审核截图 | 真实 iPhone Pro 页，1320×2868 RGB PNG；Apple COMPLETE，实际尺寸和源文件 MD5 回读一致 |
| 审核截图 ID | ac9609e1-7634-435b-b28a-2347bfe25a05 |
| Texel Pro | 6832499022 / com.lingxifox.LingXiStyle.pro / NON_CONSUMABLE |
| 内购资料 | 四语言、审核说明、截图完整；父商品 READY_TO_SUBMIT |
| 内购版本 | 39bbb7e2-42cd-49bd-8ddf-e76400ece902；审核草稿条目 READY_FOR_REVIEW |

真实设备截图最初带 alpha。经用户单独批准，用原生 ImageIO 验证像素完全不透明、去除 alpha，
保持分辨率，并逐像素核对解码后的可见值完全一致。未缩放、未绘制 UI、未伪造价格。
Apple 处理后把 fileName 规范化为 SOURCE；重跑通过源文件校验和识别同一资产，不创建第二份。
App 和内购此前已按单独批准配置为仅美国；App 免费，Pro 美国 $2.99。本轮没有重新设置价格或地区。

## 未提交的审核草稿

- 草稿：fc8c9efa-ccb4-4095-9e67-8ccbd4f60257。
- App 版本与内购版本两个条目均 READY_FOR_REVIEW。
- App Store Version 的 appStoreState / appVersionState 均 READY_FOR_REVIEW。
- submittedDate 为 null，未提交、未发布。最终提交审核由用户单独决定。

## 验证与复用

- 27 项离线 API/发布脚本测试通过，包括 JWT、写入边界、409 不重试、分发描述文件、私密文件权限、草稿幂等与 SOURCE 文件名规范化。
- generic iOS Debug 构建通过（CODE_SIGNING_ALLOWED=NO）；Release 正式签名归档、导出上传通过。
- Debug App 与扩展仍为 Automatic 开发签名，无分发描述文件覆盖。
- 重跑 upload 返回已有 VALID 构建；prepare 返回同一份草稿、同两个条目，没有重复创建。
- Trivy secret 扫描为 0 项发现；没有额外依赖或模拟器安装步骤。
- CLI 说明见 [api-client.md](api-client.md)。证据与日志保存在本地 .tmp/appstoreconnect/，不提交 Git。

未重新验证真实 App Store 购买/退款、生产 Keychain 跨进程行为、真机 HEIC 转换和全系统兼容矩阵。
本次 Apple READY_FOR_REVIEW 表示资料与构建可提审，不代表 Apple 已审核通过。
