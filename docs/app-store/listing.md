# Texel 1.7.1 — App Store listing copy

可复制到 App Store Connect 的四语言商店文案。版本 **1.7.1 (9)**，Bundle ID
`com.lingxifox.LingXiStyle`。内容依据仓库 README、`AppStoreRelease.md`、本地化文件与
实际代码行为整理；不包含虚构的价格、联系方式、备案号或审核状态。

> 发布前必须替换的占位符见文末 **Manual placeholders**，并同步到
> `docs/privacy/index.html`、`docs/support/index.html` 与 App Store Connect。

## 字段长度

Apple 的字符上限与本文文案的实际字符数（按 Unicode 字符计，含空格与换行）：

| 字段 | 上限 | zh-Hans | zh-Hant | en | ja |
| --- | ---: | ---: | ---: | ---: | ---: |
| Name | 30 | 16 | 15 | 23 | 15 |
| Subtitle | 30 | 16 | 16 | 29 | 14 |
| Promotional Text | 170 | 74 | 80 | 164 | 97 |
| Keywords | 100 | 46 | 46 | 88 | 50 |
| Description | 4000 | 576 | 580 | 1516 | 764 |
| What's New | 4000 | 70 | 72 | 233 | 102 |

> 字符数是按当前文本计算的编辑值；提交前以 App Store Connect 的实时计数器为准。
> 关键词用英文逗号分隔，不要再加空格或重复品牌词。

## 共享元数据

| 字段 | 值 | 状态 |
| --- | --- | --- |
| App 名称（App Store Connect） | 按语言填写下方 Name | 可复制 |
| 版本 | 1.7.1 | 与 `project.yml` 一致 |
| Build | 9 | 与 `CURRENT_PROJECT_VERSION` 一致 |
| Bundle ID | `com.lingxifox.LingXiStyle` | 已配置 |
| 主要分类 | Photo & Video | 建议，提交时以 App Store Connect 可选值为准 |
| 次要分类 | 可不填；如需要可选 Graphics & Design | 建议，不要为了排名堆分类 |
| 版权 | `© 2026 LingXiFox` | 来自 LICENSE；如使用其他法律实体需替换 |
| 价格 | 免费下载；Pro 为一次性非消耗型内购 | 价格由 App Store Connect 决定 |
| 内购 Product ID | `com.lingxifox.LingXiStyle.pro` | 已在 `AppStoreRelease.md` 固定 |
| 隐私政策 URL | `<PUBLIC_BASE_URL>/privacy/` | **占位，需部署后替换** |
| 支持 URL | `<PUBLIC_BASE_URL>/support/` | **占位，需部署后替换** |
| 营销 URL（可选） | `<PUBLIC_BASE_URL>/` | **占位，需部署后替换** |
| 年龄分级 | 预期 4+ | 以 App Store Connect 问卷结果为准 |
| 登录 | 不需要 | 审核备注中说明 |
| App 隐私 | Data Not Collected | 按 Apple 定义，提交前逐项确认 |

## 简体中文（zh-Hans）

App Store Connect: Simplified Chinese

### Name (30)

```text
纹粒 Texel - 纹理与颗粒
```

### Subtitle (30)

```text
给 HEIC 原片追加纹理与颗粒
```

### Promotional Text (170)

```text
iPhone 16 / 17 HEIC 原片专用。只追加纹理与颗粒，不覆盖原图、不上传照片。每天 5 张免费，纹粒 Pro 一次购买，永久不限张数。
```

### Keywords (100)

```text
HEIC,纹理,颗粒,胶片,质感,照片,修图,原图,无损,纹粒,Texel,滤镜,摄影,影像
```

### Description (4000)

```text
纹粒 / Texel 只做一件事：给 iPhone 16 / 17 拍摄的 HEIC 原片追加真实的纹理与颗粒。

不覆盖原图，不上传照片，不需要账号。所有处理都在设备本机完成，结果另存为相册中的新照片。

【只追加，不转码】
• 读取 PhotoKit 中的原始 HEIC 资源，保留 HDR、EXIF、Styles 与缩略图
• 只追加纹理与颗粒，不做滤镜、裁剪、换色或 AI 生成
• 保存后回读确认仍是 HEIC；原 Asset 不会被修改

【每天 5 张免费】
• 按设备本地自然日重置，所有入口共享额度
• 只有成功保存或导出才扣 1 张；失败、跳过、不兼容、取消不扣
• 纹粒 Pro 为一次性购买，永久不限张数，支持恢复购买

【为真实工作流设计】
• 最多 9 张批量处理，iCloud 原件真实下载并显示阶段进度
• 可取消队列，已保存照片不会被重复写入
• 结果页可在 App 内查看与分享真实 HEIC
• 分享扩展与快捷指令使用同一套转换与额度

【隐私优先】
• 开发者不运营服务器；照片不会上传到开发者服务器
• 无需登录；照片只在你明确选择时访问
• 简体中文、繁体中文、English、日本語

适用：iPhone 16 / 17 系列 HEIC 原片。Live Photo、RAW、JPEG / PNG 暂不支持。
```

### What's New (4000)

```text
• 修复分享扩展在读取阶段可能阻塞的问题
• 改进分享扩展在取消、超时与重试时的处理
• 改进快捷指令批量处理与额度提示
• 其他稳定性改进
```

## 繁體中文（zh-Hant）

App Store Connect: Traditional Chinese

### Name (30)

```text
Texel - 真實紋理與顆粒
```

### Subtitle (30)

```text
為 HEIC 原片加上紋理與顆粒
```

### Promotional Text (170)

```text
專為 iPhone 16 / 17 HEIC 原片設計。只加上紋理與顆粒，不覆蓋原圖、不上傳照片。每天 5 張免費，Texel Pro 一次購買，永久不限張數。
```

### Keywords (100)

```text
HEIC,紋理,顆粒,膠片,質感,照片,修圖,原圖,無損,紋粒,Texel,濾鏡,攝影,影像
```

### Description (4000)

```text
紋粒 / Texel 只做一件事：為 iPhone 16 / 17 拍攝的 HEIC 原片加上真實的紋理與顆粒。

不覆蓋原圖，不上傳照片，不需要帳號。所有處理都在裝置本機完成，結果另存為相簿中的新照片。

【只追加，不轉碼】
• 讀取 PhotoKit 中的原始 HEIC 資源，保留 HDR、EXIF、Styles 與縮圖
• 只加上紋理與顆粒，不做濾鏡、裁切、換色或 AI 生成
• 儲存後回讀確認仍是 HEIC；原始 Asset 不會被修改

【每天 5 張免費】
• 依裝置本地自然日重置，所有入口共用額度
• 只有成功儲存或匯出才扣 1 張；失敗、跳過、不相容、取消不扣
• Texel Pro 為一次性購買，永久不限張數，支援回復購買

【為真實工作流程設計】
• 最多 9 張批次處理，iCloud 原件真實下載並顯示階段進度
• 可取消佇列，已儲存照片不會被重複寫入
• 結果頁可在 App 內檢視與分享真實 HEIC
• 分享擴充功能與捷徑使用同一套轉換與額度

【隱私優先】
• 開發者不營運伺服器；照片不會上傳到開發者伺服器
• 無需登入；照片只在你明確選取時存取
• 簡體中文、繁體中文、English、日本語

適用：iPhone 16 / 17 系列 HEIC 原片。Live Photo、RAW、JPEG / PNG 暫不支援。
```

### What's New (4000)

```text
• 修正分享擴充功能在讀取階段可能阻塞的問題
• 改進分享擴充功能在取消、逾時與重試時的處理
• 改進捷徑批次處理與額度提示
• 其他穩定性改進
```

## English (U.S.)

App Store Connect: English (U.S.)

### Name (30)

```text
Texel - Texture & Grain
```

### Subtitle (30)

```text
Real texture & grain for HEIC
```

### Promotional Text (170)

```text
Made for iPhone 16/17 HEIC originals. Add texture and grain without overwriting the original or uploading. 5 free photos a day; Texel Pro is one-time and permanent.
```

### Keywords (100)

```text
HEIC,texture,grain,film,photo,editor,original,lossless,preserve,Texel,analog,photography
```

### Description (4000)

```text
Texel does one thing: add real texture and grain to HEIC originals shot on iPhone 16 / 17.

It never overwrites the original, never uploads your photos, and needs no account. Everything runs on your device, and the result is saved as a new photo in your library.

ONLY ADD, NEVER TRANSCODE
• Reads the original HEIC resource through PhotoKit, preserving HDR, EXIF, Styles, and thumbnails
• Adds texture and grain only — no filters, cropping, color replacement, or AI generation
• Reads the saved asset back to confirm it is still HEIC; the original asset is untouched

5 FREE PHOTOS EVERY DAY
• Resets on your device's local calendar day and is shared across every entry point
• Only a successful save or export uses one photo; failures, skips, incompatible files, and cancellations do not
• Texel Pro is a one-time purchase with unlimited photos forever; Restore Purchases is supported

BUILT FOR REAL WORKFLOWS
• Process up to 9 photos at once, with real iCloud download progress and stage-by-stage status
• Cancel a queue safely; photos already saved are never written twice
• View and share the real HEIC from the in-app result page
• The Share Extension and Shortcuts use the same conversion and quota

PRIVACY FIRST
• The developer runs no server; photos are never uploaded to the developer
• No sign-in; photos are accessed only when you select them
• Simplified Chinese, Traditional Chinese, English, Japanese

Works with HEIC originals from iPhone 16 / 17. Live Photos, RAW, JPEG, and PNG are not supported.
```

### What's New (4000)

```text
• Fixes a possible stall while the Share Extension is reading a photo
• Improves Share Extension handling for cancellation, timeouts, and retries
• Improves Shortcuts batch processing and quota messages
• Other stability improvements
```

## 日本語

App Store Connect: Japanese

### Name (30)

```text
Texel - フィルムの質感
```

### Subtitle (30)

```text
HEICに本物の質感と粒子を
```

### Promotional Text (170)

```text
iPhone 16 / 17 の HEIC 原画向け。テクスチャと粒子だけを加え、元の写真は上書きせず、アップロードもしません。1日5枚まで無料、Texel Pro は一度の購入で永久に無制限。
```

### Keywords (100)

```text
HEIC,テクスチャ,粒子,フィルム,写真,編集,原本,ロスレス,Texel,質感,アナログ,フォト
```

### Description (4000)

```text
Texel は、iPhone 16 / 17 で撮影した HEIC 原画に、本物のテクスチャと粒子を加えるためだけのアプリです。

元の写真を上書きせず、アップロードもせず、アカウントも不要。すべての処理は端末内で完結し、結果は写真ライブラリに新しい写真として保存されます。

【追加だけ、変換なし】
• PhotoKit から元の HEIC リソースを読み取り、HDR、EXIF、Styles、サムネイルを保持
• 加えるのはテクスチャと粒子だけ。フィルター、トリミング、色変換、AI 生成は行いません
• 保存後に読み戻して HEIC のままか確認。元の Asset は変更しません

【1 日 5 枚まで無料】
• 端末のローカル日付でリセット。すべての入口で同じ無料枠を共有
• 保存または書き出しに成功したときだけ 1 枚消費。失敗、スキップ、非対応、キャンセルでは消費しません
• Texel Pro は一度の購入で永久に無制限。購入の復元にも対応

【実際のワークフロー向け】
• 最大 9 枚をまとめて処理。iCloud の元画像を実際にダウンロードし、段階的な進行状況を表示
• キューは安全にキャンセル可能。保存済みの写真を二重に書き込みません
• 結果画面で本物の HEIC を表示・共有
• 共有拡張機能とショートカットも同じ変換と無料枠を使用

【プライバシー優先】
• 開発者はサーバーを運営しておらず、写真が開発者にアップロードされることはありません
• ログイン不要。写真にアクセスするのは、あなたが選択したときだけ
• 簡体字中国語、繁体字中国語、英語、日本語

対応：iPhone 16 / 17 シリーズの HEIC 原画。Live Photo、RAW、JPEG / PNG は非対応です。
```

### What's New (4000)

```text
• 共有拡張機能の読み込み時に処理が止まる可能性がある問題を修正
• 共有拡張機能のキャンセル、タイムアウト、再試行の処理を改善
• ショートカットの一括処理と無料枠の表示を改善
• その他の安定性を改善
```

## Review notes (English)

```text
Texel adds texture and grain to HEIC originals from iPhone 16/17. All processing
is on-device; the app has no account system and no developer-operated server.

Photo access: the app reads only the photo the user selects, and saves the result
as a new asset with PhotoKit. The original asset is never modified. Add to Photos
permission is requested only when the user saves.

Texel Pro is a one-time, non-consumable in-app purchase
(com.lingxifox.LingXiStyle.pro). It removes the free limit of 5 successful
conversions per local calendar day; it is not a subscription. Restore Purchases
is available on the Pro page. The app only reads Product.displayPrice and never
hard-codes a currency amount.

No login or demo account is required. No external payment or external purchase
link is used.
```

### App Review Information fields

| Field | Value |
| --- | --- |
| Sign-in required | No |
| Demo account | Not required |
| Contact name | `<REVIEW_CONTACT_NAME>` |
| Contact email | `<REVIEW_CONTACT_EMAIL>` |
| Contact phone | `<REVIEW_CONTACT_PHONE>` |
| Notes | 使用上面的 Review notes |

## App Privacy 答案（按当前代码）

在 App Store Connect → App Privacy 中，按 Apple 对“收集”的定义，当前版本应选择
**Data Not Collected**。依据：

- 开发者不运营服务器，照片不上传到开发者服务器。
- 没有账号、分析 SDK、广告 SDK、崩溃上报 SDK 或跨 App 跟踪。
- 照片只在本机处理；免费额度计数保存在本机 Keychain。
- 购买、恢复与退款由 Apple StoreKit 处理；App 不把交易数据发送给开发者。

提交前仍需按 App Store Connect 的最新问卷逐项确认。若未来加入分析、崩溃上报、
账号或任何网络服务，必须重新填写并更新隐私政策。

## 截图与合规

- 截图规格与页面清单：`docs/app-store/screenshots.md`
- 中国大陆 App 备案与合规清单：`docs/app-store/china-mainland.md`
- 隐私政策：`docs/privacy/index.html`
- 技术支持：`docs/support/index.html`

## Manual placeholders

以下值在仓库中没有真实信息，**不得虚构**；发布前必须由用户填写并替换：

| Placeholder | 用在哪里 | 说明 |
| --- | --- | --- |
| `<PUBLIC_BASE_URL>` | 本文件、App Store Connect、隐私 / 支持页互链 | GitHub Pages 或其他静态托管启用后的公开根 URL |
| `<PRIVACY_EMAIL>` | `docs/privacy/index.html` 四语言 | 隐私请求邮箱 |
| `<LEGAL_ENTITY_NAME>` | `docs/privacy/index.html` 四语言 | 备案主体 / 法律实体名称 |
| `<LEGAL_ADDRESS>` | `docs/privacy/index.html` 四语言 | 法律实体地址 |
| `<SUPPORT_EMAIL>` | `docs/support/index.html` 四语言 | 技术支持邮箱 |
| `<REVIEW_CONTACT_NAME>` | App Store Connect 审核联系信息 | 审核联系人姓名 |
| `<REVIEW_CONTACT_EMAIL>` | App Store Connect 审核联系信息 | 审核联系人邮箱 |
| `<REVIEW_CONTACT_PHONE>` | App Store Connect 审核联系信息 | 审核联系人电话 |
| `<APP_RECORD_NUMBER>` | 中国大陆 App 备案 | App 备案号；取得后填写 |
| `<ICP_FILING_NUMBER>` | 中国大陆 App Store Connect | 如与 App 备案号不同，按实际字段填写 |

> 联系邮箱与法律实体信息属于真实世界信息，仓库无法自动生成。未替换前不要把页面提交给
> App Review，也不要在 App Store Connect 中填写虚构值。
