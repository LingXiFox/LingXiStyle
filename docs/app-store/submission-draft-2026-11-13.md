# Texel 1.9.1 网站与审核草稿完成记录

2026-11-13，按主人明确授权完成线上旧文案更新与审核草稿组装。**没有提交审核，没有发布 1.9.1，没有操作真机沙盒测试或更改版本发布方式。**

## 线上网站

生产源为独立仓库 [LingXiFox/apps-site](https://github.com/LingXiFox/apps-site)，不是本仓库 `docs/privacy/` / `docs/support/` 模板。网站提交 `8cc3982ce2200354696a842bc348393aee39f550` 已经由现有 GitHub Actions [43448961809](https://github.com/LingXiFox/apps-site/actions/runs/43448961809) 成功部署到 Cloudflare Pages。

四语言产品、隐私、支持和页脚已同步：

- 隐私政策 Bundle ID 为 `com.lingxifox.Texel`，新增保险箱、任务历史、默认 7 天保留与本机 Keychain 体验凭证说明。
- 支持及产品页描述日卡、周订阅、月订阅、永久版，明确自动续期、取消、恢复购买、已有永久权益不变及每设备一次的 24 小时无扣费体验。
- 修正 Live Photo 旧兼容性说明，区分仅主帧与完整处理。
- 去掉 Pro 卡片将全部方案标为 `forever` 的固定标签；不手写任何币种的销售价。
- 明确 Texel 已在 App Store 提供，1.9.1 仍在发布准备阶段；不宣称新版本、新方案已经获批。

本地构建校验 17 个 HTML 页面通过，包含链接、语言、标题、描述、唯一 H1 与无占位符检查；四语言关键事实及生成内容自检通过，Chrome 预览确认文案与布局。Trivy secret 扫描未发现凭据。

正式部署后，四语言的首页、产品、隐私、支持共 16 个线上页面均为 HTTP 200，且响应 HTML 与本次构建逐字节一致。

## 同一审核草稿的五项内容

官方文档要求首批订阅随 App 版本通过网页准备，本轮使用 App Store Connect 网页逐项加入现有 iOS 草稿，随后用只读 API 验证。没有运行会额外加入永久商品的旧 `release prepare` 流程。

| 项目 | 资源 ID | 最终状态 |
| --- | --- | --- |
| iOS 1.9.1（11） | `4de9bf0f-d2c4-42e2-8b0e-c199928adda6` | READY_FOR_REVIEW |
| 日卡元数据版本 | `06f38c5b-63ed-48d3-b132-4bbc8ae1047f` | READY_FOR_REVIEW |
| 周订阅元数据版本 | `75005acb-b8e0-45d6-a75e-86951500d4fd` | READY_FOR_REVIEW |
| 月订阅元数据版本 | `f304fd9d-c3e1-4aa0-830d-debc11637886` | READY_FOR_REVIEW |
| Texel Pro 订阅组元数据版本 | `af895df8-c46b-4473-afb0-2f94a73ecc6e` | READY_FOR_REVIEW |

草稿 ID：`b9b8c8aa-53be-4ca0-812d-378a87d03b45`。

- 草稿与五个审核项目均为 `READY_FOR_REVIEW`，五项资源类型及 ID 与预定清单完全一致，没有重复项目或额外的旧永久商品。
- `submittedDate` 仍为空，没有发送 `submitted: true` 或点击最终「提交以供审核」。
- 关联构建仍为 `a7957ffd-b851-474a-b9e8-5158097a1b39`，build 11，处理状态 `VALID`。
- 发布方式前后均为 `AFTER_APPROVAL`；主人保留决定是否改为手动发布。
- API 校验器只执行 GET；网页的添加审核校验与最终资源状态均通过。未尝试实际审核提交，也不将 READY_FOR_REVIEW 写成审核通过。

## 证据与交接

本地证据位于 `build/asc-submit-prep-20261113/`：`before.json`、`draft-final-verified.json`、`website-live-verified.json` 和部署结果日志。凭据、联系人及网站部署密钥未提交到仓库。

剩余的真机沙盒交易验收、普通 iPhone 新版截图评估和发布方式选择由主人处理。本轮没有添加 macOS 平台或上传 Mac 构建。

本地预览服务器已停止；修改前的网站源文件保留在 `/tmp/texel-web-before-20261113/` 至主人验收。

官方依据：[首批内购 / 订阅同批送审](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)、[订阅及订阅组审核流程](https://developer.apple.com/documentation/appstoreconnectapi/submitting-subscriptions-and-subscription-groups-for-app-review)。
