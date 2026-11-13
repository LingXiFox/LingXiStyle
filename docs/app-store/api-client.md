# App Store Connect 本地客户端

从仓库根目录运行，只读检查：

```bash
uv run --frozen --script tools/appstoreconnect.py diagnose
```

DSH 可以直接通过 shell 执行同一命令；其他工作目录使用脚本绝对路径。
工具输出脱敏 JSON，失败返回非零退出码。没有安装或修改 DSH 插件。
只使用 Apple 官方 `https://api.appstoreconnect.apple.com/v1/`；不会读取浏览器、Cookie、
Apple ID 密码或 `.env`。图片二进制按官方响应上传到 Apple 临时 blobstore URL，
这些上传请求不带 JWT，也不会输出 URL。

## 认证

三个环境变量优先；也支持仓库外 `~/.config/appstoreconnect/config.json`：

```json
{
  "ASC_KEY_ID": "<your-key-id>",
  "ASC_ISSUER_ID": "<your-team-issuer-id>",
  "ASC_PRIVATE_KEY_PATH": "~/.config/appstoreconnect/keys/<your-private-key>.p8"
}
```

仅在本地编辑，配置与私钥权限建议设为 0600。私钥必须位于上述 `keys/` 目录，
不复制到仓库。客户端使用 cryptography 校验 P-256 私钥，签发 ES256 JWT，
`exp - iat = 600` 秒；提前 30 秒刷新。401 最多刷新后再请求一次，409 不重试。
JWT 只存在进程内存，不输出或写文件；HTTP 错误保留 `code`、`detail` 与
`source.pointer`，脱敏认证值、联系人、JWT 和上传 URL。

Python 3.11+；直接依赖只有经用户同意的 cryptography，版本及传递依赖锁定在
`tools/appstoreconnect.py.lock`。HTTP、JSON、PNG 校验与测试均使用标准库。

## 文案预览与更新

```bash
uv run --frozen --script tools/appstoreconnect.py plan --output .tmp/asc-plan-1.json
uv run --frozen --script tools/appstoreconnect.py apply .tmp/asc-plan-1.json --journal .tmp/asc-apply-1.json
```

`plan` 先 fetch `LingXiFox/LingXiStyle` 的 main，读取固定 commit 下的
`docs/app-store/listing.md`；预览记录 commit、SHA-256、旧值与完整新值。
不会把工作区里尚未提交的文案混入商店。可使用 `--repo /absolute/repo/path` 指定仓库。
生成文件拒绝覆盖；下一轮换用 `-2` 等新文件名，保留原始预览作为回滚依据。

工作流核对 Texel 的 Apple App ID、Bundle ID 和现有 iOS 版本；自动匹配
en-US / zh-Hans / zh-Hant / ja。应用名称、副标题和隐私政策 URL 属于
`appInfoLocalizations`，描述、关键词、推广文字和支持/营销 URL 属于
`appStoreVersionLocalizations`。资源存在用 PATCH，不存在才 POST；相同内容不写入。
新资源创建前再次查询；有并发修改时停止该项并要求重新生成预览。
每项更新后 GET 回读，日志区分 VERIFIED、UNCHANGED、HTTP 错误和本地错误。
网络结果不明时停止，下一次先重新读取，不盲目重发 POST。

未检测到以前发布过的版本时不填写 What's New，保留仓库中的版本说明。
默认只管理 `PREPARE_FOR_SUBMISSION` 版本，其他状态请先人工检查。
修改现有商店文案前保留预览中的旧值；未经用户验收不删除该记录。

审核备注需要四个真实联系人字段。请在本地创建
`~/.config/appstoreconnect/review-contact.json`，不要提交或粘贴到模型上下文：

```json
{
  "contactFirstName": "<real-first-name>",
  "contactLastName": "<real-last-name>",
  "contactEmail": "<real-email>",
  "contactPhone": "<international-phone-with-plus-and-country-code>"
}
```

```bash
uv run --frozen --script tools/appstoreconnect.py apply .tmp/asc-plan-1.json --journal .tmp/asc-apply-2.json --review-contact ~/.config/appstoreconnect/review-contact.json
```

联系人仅在执行时合入审核信息请求，不写入预览或日志。若现有四个字段完整，
工具在进程内部复用现值；缺失时先要求本地文件，避免反复触发同一个 409。

## 截图：预览、续传、回读

```bash
uv run --frozen --script tools/appstoreconnect.py screenshots --root AppStoreScreenshots/ASC --output .tmp/asc-images-1.json
uv run --frozen --script tools/appstoreconnect.py screenshots --apply-plan .tmp/asc-images-1.json --journal .tmp/asc-images-applied-1.json
```

截图根目录下为 `en`、`zh-Hans`、`zh-Hant`、`ja`，各六张 PNG，按文件名排序。
默认 ASC 子目录是本次已上传的 1206×2622 素材；原始目录中另有 1320×2868 素材。
使用哪套图片由真实像素尺寸决定，工具不缩放、不重新标注尺寸。

每次查询 `GET /v1/appAssetLibraryRefData`，动态匹配 `imageSpecs`、
`placementTypes.specMappings` 与 `features.placementPolicies.groupLimits`。
校验 PNG 签名、CRC、像素数据完整性、8-bit RGB、无 alpha/tRNS、实际分辨率、
扩展名、MIME 类型、文件大小、Apple 接受的 spec/group 和资产数量上限。
本工具仅接收当前已审核的非交错 RGB PNG；JPEG、其他色彩模式需要先另行验收。

使用当前 App Asset Library：读取 library，创建 `appAssetLibraryImages` 预约，
按 `uploadOperations` 的字节范围 PUT，最后 PATCH `uploaded: true`。
不在新 API 上发送旧截图接口的 `sourceFileChecksum`。
等待最长 120 秒，每 5 秒查询一次真实处理状态；`COMPLETE` 若尚未带尺寸与 spec，则继续等处理元数据，不提前创建 placement。
只有 `COMPLETE` / `PREPARE_FOR_SUBMISSION` / `APPROVED` 且实际尺寸与 spec 匹配才建立 placement，
最后设置和回读截图顺序。失败资产保留，删除需单独批准。

新资产用 locale + 完整 SHA-256 生成 referenceName；重跑通过服务端状态恢复同一预约，
尚未 commit 的分片会重新上传到原预约，不创建第二份资产。
浏览器已有资产没有 checksum，只在文件名、字节数、specId 唯一匹配时复用；
这不等同于远端字节 SHA-256 证明。歧义会停止，不猜测或删除。
复用现有 placement，不移除已有其他图片。

上传 URL 过期、Apple 处理失败或网络失败时返回错误并保留服务端资产；
下一次先读取状态。若 Apple 不再提供有效上传操作，需人工决定如何处理该预约。
两个客户端不要同时上传同一组素材；新预约无服务端幂等键，不能保证跨进程同时创建唯一。

## 通用官方请求

```bash
uv run --frozen --script tools/appstoreconnect.py request GET apps
uv run --frozen --script tools/appstoreconnect.py request PATCH appStoreVersionLocalizations/RESOURCE_ID --body .tmp/request.json
# The previous command only previews. Add --apply for an authorized metadata write.
```

通用 GET 支持官方 v1。`--allow-v2` 仅放行官方内购、订阅 / 订阅组本地化和应用销售地区资源；
`--release-setup` 开启另行授权的发布资料、年龄分级、价格/地区、内购资料和未提交审核草稿操作。
这些开关不代替用户对价格、地区的明确授权。删除、App 版本实际提交审核/发布、证书撤销、财务和 API 密钥修改始终禁止。
单张创意图片有独立的显式审核开关，见后文；它不能提交混有 App 或内购条目的审核草稿。
`--signing-setup` 仅允许创建证书/描述文件，不允许撤销。

2026-11-13 按 Apple OpenAPI 4.6 扩展了 `--release-setup` 的订阅配置范围：订阅组、订阅、
对应 metadata versions、v2 四语言本地化、审核截图、价格和 `subscriptionPlanAvailabilities`。
这些资源仍需显式开关；删除、`subscriptionSubmissions`、`subscriptionGroupSubmissions`、
`inAppPurchaseSubmissions` 和 App 审核提交均被拦截。35 项离线测试包含这些边界。

普通周 / 月续期使用 `planType: UPFRONT`，不是带 12 个月承诺的 `MONTHLY` 付款计划。
应先配置计划的可售地区，再按 Apple 返回的价格点逐地区创建价格；没有一次设置全部订阅地区价格的端点。
每次先读取实际状态并保存快照，409 停止；修正状态后只补尚未完成的地区，不重新创建商品或重发已验证价格。
销售地区流程保存并比较实际价格快照，不再将永久版售价固定假定为历史的 $2.99。

2026-11-13 主人新增授权中国大陆销售，当前地区策略为全部现有地区（175 个，包含 CHN），未来地区开关仍关闭。`release availability` 不再自动排除大陆；旧的 CHN 排除计划会在应用前被拒绝。四档商品的实际大陆配置与人民币价格见 [大陆销售记录](mainland-sales-2026-11-13.md)。下文 2026-11-10 的排除大陆范围仅为历史授权。

2026-11-09 的初始批准范围是仅美国。2026-11-10 用户另行批准 App 与 Pro 同步
开放所有现有地区、仅排除中国大陆；App 免费，Pro 非消耗型，美国基准 $2.99，其他地区自动本地定价。
常规文案和构建流程不会修改这些商业配置，地区变更需使用后文的显式预览/应用命令。

## 本机正式签名、归档、上传

```bash
uv run --frozen --script tools/appstoreconnect.py --signing-setup release signing
uv run --frozen --script tools/appstoreconnect.py release archive --output .tmp/asc-release-1
uv run --frozen --script tools/appstoreconnect.py release upload --output .tmp/asc-release-1
uv run --frozen --script tools/appstoreconnect.py --allow-v2 --release-setup release prepare --output .tmp/asc-release-1
```

当前验证环境固定为稳定版 Xcode 27.2 / iPhoneOS 27.2 SDK；无需下载模拟器运行时。
升级 Xcode 时需同步更新 `release_appstore.py` 的 SDK/Xcode 检查并重新验收。
以后版本通过顶层 `--version` 指定，版本号/构建号仍在 `project.yml` 修改并重新生成项目。

已授权建立的证书、私钥和状态保存在 `~/.config/appstoreconnect/signing/`，目录 0700、文件 0600。
`signing` 验证本地私钥与 Apple 证书、公钥、Team 和有效期，复用 Keychain 现有身份；
缺少身份时用 Apple 原生工具导入，临时 PKCS#12 用随机密码并在退出时删除。
首次 codesign 如请求 Keychain 授权，需要用户在本机允许，不把密码传给脚本。
该命令不会再次创建分发证书；当前证书失效时需要另行授权更新。

为两个准确 Bundle ID 复用或创建 IOS_APP_STORE 描述文件，校验证书、Team、有效期、
非调试 entitlement、App ID 和共享 Keychain 组后安装到 Xcode 用户目录。
Release 手动签名、Debug 自动开发签名；本地 xcconfig 提供两个 profile UUID，Git 只保存变量引用。
Framework 仅嵌入主 App，Share Extension 通过 `@executable_path/../../Frameworks` 加载同一份 framework。

`archive` 运行 XcodeGen 和官方 `xcodebuild archive`，检查两个 bundle 的签名、版本/构建号、
共享 Keychain entitlement、分发描述文件、SDK、扩展无嵌套 Frameworks，以及没有本地 StoreKit 配置。
输出目录禁止覆盖已有 Archive/日志；失败后选择新目录，保留错误证据。
`upload` 通过 `xcodebuild -exportArchive`、本地手动签名、ASC API Key 上传，保留原构建号，
不使用云端签名、浏览器认证或重签名服务。若相同版本和构建号已在 Apple 上出现，先返回现有状态，避免重复上传。

`prepare` 最长 30 分钟、每分钟查询 Apple 实际处理状态，VALID 后关联当前版本，
声明与 App Info.plist 一致的非豁免加密状态，并把 App 和当前内购版本加入未提交审核草稿。
先读现有草稿和条目，避免重复创建；任一 409 立即返回原始原因，绝不设置 `submitted`。
处理状态写入 `processing.json`，通过后保存 `ready-for-user-review.json`。

内购审核截图单独使用已审核的真实 Pro 页面 RGB PNG：

```bash
uv run --frozen --script tools/appstoreconnect.py --allow-v2 --release-setup release review-screenshot --screenshot /absolute/path/texel-pro-review-rgb.png
```

使用父商品的官方审核截图接口；它与 App Asset Library、1024×1024 推广图是不同资源。
按 Apple 预约 PUT 分片，提交 MD5 后回读实际处理状态与校验和；已有预约续传，不删除或替换不同截图。
PUT 仅允许 Apple 的 blobstore 子域或官方 Transporter 文档中的
`northamerica-1.object-storage.apple.com`，不带 JWT，不跟随重定向。
本次真实设备截图经用户批准用原生 ImageIO 去掉完全不透明的 alpha 通道，保留 1320×2868，
并逐像素比较解码结果一致；原截图保留在本地 `.tmp/`，不提交 Git。

## 验证与边界

```bash
uv run --frozen --script tools/appstoreconnect.py self-test
```

离线测试不读取生产配置或联系 Apple，覆盖真实 ES256 验签、600 秒有效期、刷新、
401 次数上限、409 原始字段/脱敏、来源解析、已有/缺失资源、并发改动、回读、
PNG 拒绝条件、动态规格、上传范围/主机/无 JWT、已有资产重跑与预约恢复。
真实执行记录见同目录 `api-report-2026-11-09.md`。

官方参考：

- [JWT 认证](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests)
- [区域语言代码](https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes)
- [动态资产规格](https://developer.apple.com/documentation/appstoreconnectapi/discovering-asset-specifications)
- [图片预约、上传、提交](https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets)
- [Placement 与排序](https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces)
- [当前截图要求](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)


## 已上架版本：扩展地区与搜索创意图

2026-11-10 用户明确批准 App 与 Pro 同步开放全部现有地区、只排除 CHN，
保留美国 $2.99 基准和自动本地定价，不开启未来地区。其他任务不得把此授权视为通用授权。

```bash
uv run --frozen --script tools/appstoreconnect.py --allow-v2 --release-setup release availability --output .tmp/market-preview
uv run --frozen --script tools/appstoreconnect.py --allow-v2 --release-setup release availability --apply-plan .tmp/market-preview/availability-plan.json --output .tmp/market-preview
```

先查询全部 territory、App/IAP 可售地区、未来地区开关、美国基准和现有手工价，
生成精确增删清单。应用预览时重新核对价格和 Apple 当前地区全集；只 PATCH 需要变化的
territoryAvailabilities.available，不改日期或预购状态。IAP 使用官方 POST 更新完整地区集合。
先完成 IAP 并回读，再修改 App；每个已修改地区写入进度，失败不循环重试，
重跑从真实状态恢复。最终 App 与 IAP 都必须正好等于当前所有地区减 CHN，价格必须与预览一致。
本流程不修改价格、协议、DSA、身份、税务或银行资料；合规限制如实留在 contentStatuses 中。

Apple 搜索创意素材与普通 App 截图分开；缺少时回退使用截图。新图片先校验当前
appAssetLibraryRefData 的类型映射、实际像素、PNG CRC/解压、RGB 和无 alpha，
用 SHA-256 referenceName 复用预约，只有 Apple 实际 specId/尺寸匹配才继续。

```bash
uv run --frozen --script tools/appstoreconnect.py --allow-v2 --release-setup release creative --image /absolute/approved-search.png --submit-asset-review --publish-approved --watch-approval --output .tmp/creative-run
```

这三个开关必须在用户批准该具体图片、独立素材审核和获批后使用之后才启用。
`--submit-asset-review` 创建只含这一张图片的审核草稿，客户端在 PATCH submitted 前
再次 GET 草稿和所有条目，拒绝其他图片、App 版本、内购或任何混合内容。
未启用图片审核作用域时，既有 App 提审保护仍生效。
`--publish-approved` 仅在图片 APPROVED 且原版本仍 READY_FOR_SALE 时，为当前四语言添加搜索 placement。
不会覆盖不同的已有素材，也不会删除资源。无 1.7.2 或新 IPA 创建步骤。
`--watch-approval` 每分钟查询一次，最多 24 小时，遇到 FAILED/REJECTED/ARCHIVED 立即退出。
等待期间 creative-state.json 保存真实状态；获批后才绑定页面，未获批不宣称已展示。
后台任务是有明确期限的授权素材发布工作；结束后应清理临时 worktree 和工具进程。

图片本地保存在 AppStoreScreenshots/Creative/（仍不提交 Git），旁边的 prompt 文件记录
内置生图提示词、原始 1536×1024 和用户批准的 ImageIO 3072×2048 放大导出。
它是品牌创意插画，不作为真实 App 截图，也不宣称原生生成分辨率达到 3072。
