# Texel / 纹粒 — 发布资料索引

本目录是 1.9.1 的可部署发布资料与可复制文案。所有页面均为静态 HTML/CSS，不依赖构建工具、
外部字体、JavaScript 或第三方资源。

## 文件

| 路径 | 内容 |
| --- | --- |
| `listing.md` | 四语言 App Store 名称、副标题、推广文本、关键词、描述、What's New、审核备注、占位符 |
| `release-notes-1.9.1.md` | 1.9.1 四语言 What's New 与发布备注 |
| `universal-purchase.md` | iOS / iPadOS / macOS 通用购买、Bundle ID、签名能力与 App Store Connect 手动步骤 |
| `screenshots-1.9.1.md` | 1.9.1 分平台截图规格、页面清单与本轮 iPad / Duo 实拍范围 |
| `release-report-2026-11-13.md` | 1.9.1 签名构建上传、四档商品价格与四语言 iPad / Duo 截图验收 |
| `screenshots.md` | iPhone 截图规格、6 页清单、四语言截图文案、捕获步骤 |
| `china-mainland.md` | 中国大陆 App 备案 / ICP 备案、权限、内购、数据出境清单 |
| `../index.html` | 公开首页（纹粒 / Texel、1.9.1、隐私与支持入口） |
| `../privacy/index.html` | 四语言隐私政策 |
| `../support/index.html` | 四语言技术支持 / FAQ |
| `../styles.css` | 共享响应式样式（浅色 / 深色、Reduce Motion） |

## 本地预览

在仓库根目录：

```bash
python3 -m http.server 8080 --directory docs
```

然后打开：

- `http://localhost:8080/`
- `http://localhost:8080/privacy/`
- `http://localhost:8080/support/`

检查四语言锚点（`#zh-Hans`、`#zh-Hant`、`#en`、`#ja`）、浅色/深色、窄屏布局与键盘焦点。
页面不发送网络请求，也不设置 Cookie。

## 部署到 GitHub Pages

仓库的静态站点根目录是 `docs/`。启用方式（二选一）：

1. GitHub 仓库 → **Settings → Pages → Build and deployment → Deploy from a branch**，
   Branch 选择 `main`，Folder 选择 `/docs`。
2. 如使用自定义域名，在 Pages 设置中填写域名并按 GitHub 指引配置 DNS 与 HTTPS。

部署后得到类似 `https://<owner>.github.io/LingXiStyle/` 的地址。把它作为
`<PUBLIC_BASE_URL>` 替换到：

- `docs/app-store/listing.md` 的共享元数据与 Manual placeholders
- App Store Connect 的隐私政策 URL、支持 URL、营销 URL
- `docs/privacy/index.html`、`docs/support/index.html` 的互相链接（如需要绝对地址）

> GitHub Pages 无需 ICP 备案，但中国大陆访问可能不稳定。若面向中国大陆正式发布，
> 需按 `china-mainland.md` 评估境内托管与 ICP 备案；不要伪造备案号。

## 发布前必须替换 / 完成

以下不是仓库能自动生成的真实世界信息，详见 `listing.md` 与 `china-mainland.md`：

- [ ] `<PUBLIC_BASE_URL>`：部署后的 HTTPS 根地址。
- [ ] `<PRIVACY_EMAIL>`：隐私请求邮箱。
- [ ] `<LEGAL_ENTITY_NAME>` / `<LEGAL_ADDRESS>`：法律实体与地址。
- [ ] `<SUPPORT_EMAIL>`：技术支持邮箱。
- [ ] `<APP_RECORD_NUMBER>`：中国大陆 App 备案号（取得后填写）。
- [ ] `<ICP_FILING_NUMBER>`：如适用，网站 ICP 备案号。
- [ ] `<REVIEW_CONTACT_NAME>` / `<REVIEW_CONTACT_EMAIL>` / `<REVIEW_CONTACT_PHONE>`：
      App Review 联系人。
- [ ] 1.9.1 其余平台截图：本轮补齐 iPad / iPhone Duo，结果见发布记录；普通 iPhone 仍是历史套图，macOS 尚未补拍。
- [x] 真实 App 截图：1.7.1 四语言各 6 张已捕获，保存在本地 `AppStoreScreenshots/`（不提交仓库）；Pro 页待商品配置后补拍。
- [x] App target 已提供 `PrivacyInfo.xcprivacy`（`UserDefaults` / `CA92.1`）。
- [x] Share Extension 已提供独立 `PrivacyInfo.xcprivacy`（`FileTimestamp` / `C617.1`，用于清理自身临时目录）；
      Shortcuts 复用 App 清单，未来新增 required reason API 或第三方 SDK 时仍需补充。

## 原则

- 文案与代码行为一致；不虚构价格、联系方式、备案号、审核状态或媒体评价。
- 保留品牌「纹粒 / Texel」、每日免费 5 张与多档 Pro（日卡 / 周订阅 / 月订阅 / 永久）。
- 不生成虚假 App 截图；不把测试 fixture 用作商店素材。
- 页面保持简洁、响应式、可键盘访问，并尊重 Reduce Motion。
- 本目录只描述发布准备，不代表 App 已提交、已备案或已通过审核。
