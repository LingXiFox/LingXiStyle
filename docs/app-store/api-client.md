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
等待最长 120 秒，每 5 秒查询一次真实处理状态；没有假进度。
只有 `PREPARE_FOR_SUBMISSION` / `APPROVED` 且实际尺寸与 spec 匹配才建立 placement，
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

通用 GET 可读取官方 v1 资源；POST/PATCH 写入仅允许商店本地化、审核资料、
图片预约/提交、placement 与排序，使用官方 JSON:API 请求体。
没有删除、提审、发布、价格、销售地区、证书、财务或密钥修改接口。
内购只查询 `apps/{id}/inAppPurchasesV2`；商品不存在时预览四语言创建方案，
不创建商品。现代商品创建接口是官方 `/v2/inAppPurchases`，超出本轮 v1 限定。
美国 $2.99 是用户目标，尚未设置，实际价格和销售地区需另行批准。

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
