# Texel 1.7.1 — App Store screenshots

本文件只定义**截图规格、页面清单、四语言文案与拍摄步骤**。仓库中不包含、也不生成
App 截图；所有截图必须从真实运行的 App 捕获。不要用合成图、设计稿或伪造的界面代替。

## 1. Apple 规格（iPhone）

App Store Connect 的尺寸要求会随 Apple 政策调整，提交前以 App Store Connect 当前提示为准。
当前建议：

| 项目 | 要求 |
| --- | --- |
| 必需尺寸 | 6.9 英寸 iPhone（iPhone 16 Pro Max / 17 Pro Max），竖屏 **1320 × 2868** |
| 可选尺寸 | 6.5 英寸，竖屏 **1284 × 2778**（或 1242 × 2688，以 App Store Connect 接受值为准） |
| 数量 | 每种语言 3–10 张；建议 6 张 |
| 格式 | PNG 或 JPG，RGB，扁平化，**无 alpha / 透明通道** |
| 方向 | 竖屏；不要混用横屏 |
| 顺序 | 同一语言内顺序固定；多语言版本保持相同页面顺序 |
| 状态栏 | 满信号、满电量、时间 9:41；不要显示真实运营商或个人信息 |
| 内容 | 只展示真实 App UI 与已获授权的照片；不得展示虚构价格、评分、媒体引用或“已上架”状态 |

> 6.9 英寸是当前 App Store Connect 的必需主尺寸。若 Apple 后续只要求 6.5 英寸，仍建议保留
> 6.9 英寸素材；不要为了尺寸猜测而生成假图。

## 2. 拍摄前准备

1. 使用 iPhone 16 Pro Max 或 iPhone 17 Pro Max 模拟器（或真机），系统语言分别设为
   zh-Hans / zh-Hant / en / ja。
2. 准备一组**有明确再分发授权**的实拍 HEIC 照片。不要使用 `Tests/Fixtures/IMG_5296.HEIC`：
   该文件只允许作为测试 fixture，许可明确禁止再分发，不能进入商店素材。
3. 用真实转换流程生成结果；不要手动改 UI 文案、伪造进度或拼接不存在的页面。
4. 需要展示 Pro 时，只显示实时加载的 `Product.displayPrice`；加载失败就展示错误与重试，
   或改用额度页/Pro 入口，不要在截图中写任何价格。
5. 截图内不要出现邮箱、设备名、真实姓名、位置、相册中的私人照片或诊断信息。

### 状态栏覆盖（模拟器）

```bash
xcrun simctl status_bar booted override \
  --time '9:41' \
  --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 --operatorName ''
```

拍摄完成后恢复：

```bash
xcrun simctl status_bar booted clear
```

### 捕获

```bash
mkdir -p screenshots/zh-Hans
xcrun simctl io booted screenshot screenshots/zh-Hans/01-home.png
```

逐页操作 App，等待真实状态出现后再截图。不要用定时器或静态 mock 制造“处理中”的画面。

## 3. 页面清单（6 张，顺序固定）

| # | 页面 | 必须展示的真实状态 | 不要展示 |
| ---: | --- | --- | --- |
| 1 | 首页 / 选择入口 | 品牌、当前免费额度、进入选片的主按钮 | 虚构的“Editor's Choice”、评分、媒体 logo |
| 2 | 已选照片 | 3 张左右已选 HEIC 缩略图、可继续添加、开始按钮 | 私人照片、未经授权的图片 |
| 3 | 转换中 | 真实阶段（读取 / 下载 / 处理 / 保存）与真实 iCloud 进度 | 假百分比、假剩余时间、假队列 |
| 4 | 结果页 | 已保存的新 Asset、HEIC 回读确认、应用内预览/分享入口 | “原图已覆盖”之类错误描述 |
| 5 | 额度 / Pro 入口 | 今日额度用完或 Pro 入口；如显示价格，必须是实时 displayPrice | 硬编码价格、虚构折扣、倒计时 |
| 6 | 设置 | 语言切换、隐私/支持入口、版本 1.7.1 | 真实邮箱、内部诊断、未公开开关 |

### 可选第 7 张

分享扩展或快捷指令的真实界面，仅在已经完成真机/模拟器验证后添加；不要用未验证的流程充数。

## 4. 四语言文案

每张图建议只放 1 行主标题 + 1 行短说明；文字不要遮挡关键 UI。下列文案可直接叠加到截图上，
也可只作为 App Store Connect 的截图说明。**不得加入价格、排名、奖项或用户评价。**

### 简体中文（zh-Hans）

| # | 主标题 | 说明 |
| ---: | --- | --- |
| 1 | 只加纹理，不动原图 | 给 iPhone 16 / 17 的 HEIC 原片追加质感 |
| 2 | 每天 5 张，成功才计数 | 失败、跳过、不兼容、取消都不扣 |
| 3 | 真实的 iCloud 下载进度 | 阶段由引擎回调驱动，不造假进度 |
| 4 | 保存后回读，确认仍是 HEIC | 新照片入相册，原 Asset 不被修改 |
| 5 | 一次购买，永久不限张数 | 纹粒 Pro，非订阅 |
| 6 | 四种语言，随你切换 | 简体中文、繁體中文、English、日本語 |

### 繁體中文（zh-Hant）

| # | 主標題 | 說明 |
| ---: | --- | --- |
| 1 | 只加紋理，不動原圖 | 為 iPhone 16 / 17 的 HEIC 原片加上質感 |
| 2 | 每天 5 張，成功才計數 | 失敗、跳過、不相容、取消都不扣 |
| 3 | 真實的 iCloud 下載進度 | 階段由引擎回呼驅動，不造假進度 |
| 4 | 儲存後回讀，確認仍是 HEIC | 新照片進入相簿，原始 Asset 不被修改 |
| 5 | 一次購買，永久不限張數 | Texel Pro，非訂閱 |
| 6 | 四種語言，隨你切換 | 簡體中文、繁體中文、English、日本語 |

### English (U.S.)

| # | Headline | Supporting line |
| ---: | --- | --- |
| 1 | Texture, not a rewrite | Real grain for iPhone 16 / 17 HEIC originals |
| 2 | 5 free a day, counted on save | Failures, skips, incompatible files, and cancellations do not count |
| 3 | Real iCloud progress | Stage updates come from the engine, never a timer |
| 4 | Read back, confirmed HEIC | A new photo is saved; the original asset is untouched |
| 5 | One purchase, unlimited | Texel Pro is not a subscription |
| 6 | Four languages | Simplified Chinese, Traditional Chinese, English, Japanese |

### 日本語

| # | 見出し | 補足 |
| ---: | --- | --- |
| 1 | 質感だけを、原本のまま | iPhone 16 / 17 の HEIC 原画に本物の粒子を |
| 2 | 1 日 5 枚、保存できた分だけ | 失敗、スキップ、非対応、キャンセルは消費しません |
| 3 | iCloud の実際の進捗 | エンジンのコールバックに基づく表示。タイマーは使いません |
| 4 | 保存後に読み戻して HEIC を確認 | 新しい写真を保存。元の Asset は変更しません |
| 5 | 一度の購入で無制限 | Texel Pro はサブスクリプションではありません |
| 6 | 4 言語に対応 | 簡体字中国語、繁体字中国語、英語、日本語 |

## 5. 交付前检查

- [ ] 6.9 英寸竖屏 1320 × 2868，PNG/JPG，无 alpha
- [ ] 每种语言 3–10 张，顺序一致；四语言都已准备或明确只发布已完成的语言
- [ ] 所有画面来自真实 App，未修改 UI、未伪造进度/价格/评分
- [ ] 照片有再分发授权，未使用 `Tests/Fixtures/IMG_5296.HEIC`
- [ ] 状态栏 9:41、满电、无真实运营商/个人信息
- [ ] 截图中无邮箱、设备名、真实姓名、位置或诊断信息
- [ ] 价格（如出现）来自实时 `Product.displayPrice`，且与提交地区一致
- [ ] 截图文案与 `docs/app-store/listing.md` 的版本/功能描述一致
- [ ] 不展示“已通过审核”“App Store 推荐”等未发生状态

## 6. 人工待办

- [ ] 准备有再分发授权的 HEIC 样片（不要用测试 fixture）。
- [ ] 在 iPhone 16/17 Pro Max 模拟器或真机按上面 6 个页面逐页捕获。
- [ ] 将截图放入 App Store Connect 对应语言；如暂不本地化截图，至少完成 zh-Hans 与 en。
- [ ] 逐张核对无隐私信息、无虚构价格、无未验证功能。
- [ ] 如后续新增页面或改版，重新捕获；不要复用旧版截图冒充 1.7.1。

> 本文件是拍摄与交付规范，不是截图本身。仓库不会生成或提交虚假的 App 截图。
