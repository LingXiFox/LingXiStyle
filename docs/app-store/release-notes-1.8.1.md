# 纹粒 / Texel 1.8.1 版本说明

- 版本：1.8.1（build 10）
- Bundle ID：`com.lingxifox.Texel`
- 日期：2026-11-11
- 适用：iPhone 16 / 17、iPhone Duo（iOS 18.0+）；iPad 不属于发布支持范围
- 内购：未新增付费项；纹粒 Pro 仍为一次性非消耗型购买

以下文案可直接粘贴到 App Store Connect 的「What's New」字段。四语言均未超过 4000 字符。

## 简体中文（zh-Hans）

```text
实况照片来了。现在可以给实况照片追加纹理与颗粒，并另存为一张新的实况照片。

• 两种处理方式：仅处理主帧更快；完整处理会让动态画面也带上同样的质感，同时保留声音、关键帧与配对关系
• 额度不变：每张实况照片只计 1 张额度，完整处理也一样；90+ 帧、任务内重试都不重复扣
• 全新 9 步教程：首次启动逐步介绍原理、适用照片、实况模式、结果查看与额度，可直接在教程里设好默认处理方式；之后可从首页或设置随时重看
• iPhone Duo：外屏可完成选片、转换与结果全流程；宽屏时左队列、右详情双栏联动
• 其他稳定性改进
```

## 繁體中文（zh-Hant）

```text
實況照片來了。現在可以為實況照片加上紋理與顆粒，並另存為一張新的實況照片。

• 兩種處理方式：僅處理主幀更快；完整處理會讓動態畫面也帶上同樣的質感，同時保留聲音、關鍵幀與配對關係
• 額度不變：每張實況照片只計 1 張額度，完整處理也一樣；90+ 幀、任務內重試都不重複扣
• 全新 9 步教學：首次啟動逐步介紹原理、適用照片、實況模式、結果檢視與額度，可直接在教學裡設好預設處理方式；之後可從首頁或設定隨時重看
• iPhone Duo：外螢幕可完成選片、轉換與結果全流程；寬螢幕時左佇列、右詳情雙欄連動
• 其他穩定性改進
```

## English (U.S.)

```text
Live Photos are here. Add texture and grain to a Live Photo and save the result as a new Live Photo.

• Two processing modes: Still Frame Only is faster; Full Processing gives the motion frames the same texture and grain while preserving audio, keyframes, and pairing
• Same quota: one Live Photo always counts as one photo, even with Full Processing; 90+ frames and in-task retries never charge twice
• New 9-step tutorial: on first launch, learn how it works, which photos are supported, how Live Photo modes differ, where results go, and how quota works — and set your default mode right in the tutorial. Reopen it anytime from Home or Settings
• iPhone Duo: complete the full select, convert, and result flow on the outer display; on wider screens, a queue rail and detail pane work together
• Other stability improvements
```

## 日本語

```text
ライブフォトに対応しました。ライブフォトにテクスチャと粒子を加え、新しいライブフォトとして保存できます。

• 2 つの処理方法：メインフレームのみは高速。完全処理では動画の各フレームにも同じ質感を加え、音声、キーフレーム、ペアリングを保持します
• 無料枠はそのまま：ライブフォト 1 枚は完全処理でも 1 枚分。90 フレーム以上でも、タスク内の再試行でも二重に消費しません
• 新規 9 ステップチュートリアル：初回起動時に仕組み、対応写真、ライブフォトのモード、結果の確認方法、無料枠を順番に説明。チュートリアル内で既定の処理方法を設定でき、後からホームや設定でいつでも再表示できます
• iPhone Duo：外側ディスプレイで選択、変換、結果まで完了。広い画面では左のキューと右の詳細を連動表示
• その他の安定性を改善
```

## 发布备注

- 本次没有新增订阅、没有调整价格、没有新增付费功能。
- 实况照片的两种模式都只在整张照片成功保存后扣 1 张额度；仅处理主帧与完整处理计价相同。
- 教程可跳过，跳过或完成后不会在后续启动时自动弹出；首页与设置保留「使用教程」入口。
- Duo 内屏已通过 DeviceHub 姿态切换进入，验证 669 × 951 pt 双栏、设置与 Pro sheet；内屏完整转换与折叠中间态仍需在具备条件的设备上复验。
- 发布版与 Debug 配置均为 iPhone-only（`TARGETED_DEVICE_FAMILY=1`），不使用 iPad。
- 本机没有真机与 iOS 18 / 26 运行时；上述结果来自模拟器与自动化测试，不构成真机或全系统版本验收。
