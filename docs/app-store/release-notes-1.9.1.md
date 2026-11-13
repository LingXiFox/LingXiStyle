# 纹粒 / Texel 1.9.1 版本说明

- 版本：1.9.1（build 11）
- Bundle ID：`com.lingxifox.Texel`（iOS / iPadOS / macOS，Universal Purchase）
- 日期：2026-11-12
- 适用：iPhone 16 / 17、iPhone Duo、iPad、Apple Silicon Mac（iOS / iPadOS 18.0+、macOS 15.0+）
- 内购：新增日卡、周订阅、月订阅；永久版沿用原商品 ID，老用户权益不变

以下文案可直接粘贴到 App Store Connect 的「What's New」字段。四语言均未超过 4000 字符。

## 简体中文（zh-Hans）

```text
纹粒 1.9.1：成果有了保险箱，任务可以追溯，iPad 与 Mac 原生登场。

• 成果保险箱：转换结果默认在 App 内保留 7 天，可随时预览、重新保存、导出或删除；重存不扣额度，保留期限可在设置里改成 3 / 7 / 14 / 30 天或永久
• 任务历史与恢复：每次任务都有时间、张数、状态与结果记录；失败可单独重试，意外退出后重启会识别中断任务，未确认保存的额度自动归还
• 多档 Pro：新增 24 小时日卡、周订阅与月订阅，与永久版权益相同、只是期限不同；已购永久版的老用户不受影响
• 免费体验：新用户可一键领取 24 小时 Pro 体验，不订阅、不扣费，到期自动回到实际权益
• iPad 原生界面：两栏首页、居中内容列，支持横竖屏、多窗口与把 HEIC 直接拖进来
• Mac 原生 App：拖放或从 Finder 导入、批量转换、自定义导出文件夹、任务历史与保险箱，以及键盘快捷键
• 其他稳定性改进
```

## 繁體中文（zh-Hant）

```text
紋粒 1.9.1：成果有了保險箱，任務可以追溯，iPad 與 Mac 原生登場。

• 成果保險箱：轉換結果預設在 App 內保留 7 天，可隨時預覽、重新儲存、匯出或刪除；重存不扣額度，保留期限可在設定裡改成 3 / 7 / 14 / 30 天或永久
• 任務歷史與恢復：每次任務都有時間、張數、狀態與結果紀錄；失敗可單獨重試，意外退出後重啟會辨識中斷任務，未確認儲存的額度自動歸還
• 多檔 Pro：新增 24 小時日卡、週訂閱與月訂閱，與永久版權益相同、只是期限不同；已購永久版的老用戶不受影響
• 免費體驗：新用戶可一鍵領取 24 小時 Pro 體驗，不訂閱、不扣費，到期自動回到實際權益
• iPad 原生介面：兩欄首頁、居中內容欄，支援橫豎螢幕、多視窗與把 HEIC 直接拖進來
• Mac 原生 App：拖放或從 Finder 匯入、批次轉換、自訂匯出資料夾、任務歷史與保險箱，以及鍵盤快速鍵
• 其他穩定性改進
```

## English (U.S.)

```text
Texel 1.9.1: a vault for your results, a real task history, and native iPad and Mac apps.

• Result Vault: converted photos stay in the app for 7 days by default. Preview, re-save, export, or delete them anytime — re-saving never uses quota. Change retention to 3 / 7 / 14 / 30 days or forever in Settings
• Task history and recovery: every task records time, photo count, state, and results. Retry only what failed; after an unexpected quit, interrupted tasks are detected and unconfirmed quota reservations are returned
• More Pro options: 24-hour day pass, weekly, and monthly subscriptions join the lifetime purchase. Same benefits, different terms; existing lifetime owners keep everything
• Free trial: new users can claim 24 hours of Pro in one tap — no subscription, no charge, and it simply expires back to your regular access
• Native iPad layout: two-column home, centered content, portrait and landscape, multiple windows, and drag-and-drop HEIC import
• Native Mac app: drag-and-drop or Finder import, batch conversion, custom export folder, task history and vault, plus keyboard shortcuts
• Other stability improvements
```

## 日本語

```text
紋粒 1.9.1：変換結果の保管庫、タスク履歴、そして iPad と Mac のネイティブアプリ。

• 成果の保管庫：変換結果は既定で 7 日間アプリ内に保持。プレビュー、再保存、書き出し、削除がいつでも可能で、再保存では無料枠を消費しません。保持期間は設定で 3 / 7 / 14 / 30 日または無期限に変更できます
• タスク履歴と復元：各タスクの日時、枚数、状態、結果を記録。失敗した写真だけを再試行でき、予期せず終了しても再起動時に中断タスクを検出し、未確定の無料枠を戻します
• Pro の選択肢を拡充：24 時間のデイパス、週額、月額サブスクを追加。買い切りと同じ特典で期間だけが異なります。既存の買い切りユーザーはそのまま利用できます
• 無料体験：新規ユーザーはワンタップで 24 時間の Pro を試せます。サブスク登録も課金もなく、期限が切れると通常の権利に戻ります
• iPad ネイティブ UI：2 カラムのホーム、中央寄せのコンテンツ、縦横画面、複数ウィンドウ、HEIC のドラッグ＆ドロップに対応
• Mac ネイティブアプリ：ドラッグ＆ドロップや Finder からの読み込み、バッチ変換、書き出しフォルダの指定、タスク履歴と保管庫、キーボードショートカット
• その他の安定性を改善
```

## 发布备注

- 永久版沿用 `com.lingxifox.LingXiStyle.pro`，已购用户升级后权益不变；日卡 `...pro.day` 为非续期订阅，周 / 月订阅属于同一订阅组，切换档次由系统按升级 / 降级规则处理。
- 价格只来自 `Product.displayPrice`。`Configuration.storekit` 保留本地测试价；2026-11-13 主人批准的正式美国基准价为永久 $7.99、日卡 $0.49、周 $0.99、月 $1.99，其他地区按 Apple 返回的价格点配置。永久商品 ID 不变，已购用户权益不变。
- 免费体验每台设备一次，记录在本机 Keychain；卸载重装不会重置，也不上传照片或设备信息。
- 保险箱成果存放在 App 沙盒，默认保留 7 天且不参与 iCloud 备份；删除 App 会一并清除，云端相册中的已保存照片不受影响。
- 分享扩展与快捷指令使用各自容器，不读取主 App 的保险箱与任务历史。
- 本机验证范围：iOS / iPadOS 27.2 模拟器、macOS 15（Apple Silicon）本机运行与自动化测试；未覆盖真机、真实交易、iOS 18 / 26 运行时。详见 `TEST_REPORT.md`。
