# AGENTS.md

本文件约束在本仓库工作的编码代理。项目目标与交付要求来自项目书
（不随仓库分发；以仓库内 README、AGENTS 与 TEST_REPORT 为准）。

## 项目一句话

本地 SwiftUI App：读取 PhotoKit 中 iPhone 16/17 的 HEIC **原始资源文件**，只追加第三代
Texture / Grain，另存为相册新照片。原图不覆盖、不转码、不上传。

## 构建与验证

```bash
xcodegen generate
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates build

xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
```

改了 `project.yml` 或新增文件后必须重新 `xcodegen generate`，否则 target 源列表不会更新
（历史坑：测试 target 空源，报 `Cannot find executable for CFBundle ... xctest`）。

## 不可破坏的约束

1. **唯一入口**：App、快捷指令、分享扩展都只能调用
   `Services/Sources/LingXiServices/ConversionService.swift` 的 `ConversionService.shared.convert`。
   不要在各入口各写一份编码管线。
2. **不重编码**：转换路径禁止经过 `UIImage` / `CGImageDestination` / `sips`。
   `UIImage` 只用于缩略图与预览。
3. **不覆盖原图**：只用 `PHAssetCreationRequest.addResource(with: .photo, fileURL:)` 新建 Asset，
   保存后必须回读确认仍是 HEIC。
4. **不造假进度**：阶段只能由引擎真实回调驱动；没有百分比，不用定时器推进业务状态。
5. **兼容性先判后转**：非 HEIF、Live Photo、RAW、已带第三代质感必须在
   `CompatibilityEvaluator` 里明确处理，错误文案用中文，原始码只放诊断。
6. **设计令牌**：颜色、间距、圆角、字体全部走 `App/Sources/DesignSystem/Tokens.swift`；
   动效走 `Motion.swift`，循环动画必须尊重 Reduce Motion。
7. **同一个服务二进制**：`PhotoLibraryService` 与 `ConversionService` 属于 `LingXiServices`
   framework，App 与 ShareExtension 都链接它，不要复制源文件到两个 target。

## 代码约定

- Swift 5 模式，iOS 18+；App 为 SwiftUI，分享扩展用 `UIHostingController` 承载 SwiftUI。
- 注释与 commit message 用英文；用户可见文案用中文。
- 新增公开 API 要显式 `public`，并保持值类型 `Sendable`。
- 临时文件只写 `FileManager.default.temporaryDirectory`，任务结束删除；探针脚本放 `/tmp` 或 `.tmp/`，
  不提交。
- 不引入第三方 UI 框架、不新增网络依赖。

## 测试与交付

- 修改 Kit / Engine 必须跑对应 macOS 测试 scheme；修改 App 必须至少做一次
  `generic/platform=iOS` 构建。
- 真机验证状态以 `TEST_REPORT.md` 为准，不得把「编译通过」写成「真机通过」。
- 已有 48MP 实拍 HEIC 的引擎层验证，记录见 `TEST_REPORT.md`；主 App 主流程已由机主确认，分享扩展与快捷指令仍需真机确认，不得把引擎通过写成 App 通过。
- 修改 HEIF 解析后必须跑 `LingXiKitTests` 的 `iref` 回归用例。

## 目录速查

| 路径 | 内容 |
| --- | --- |
| `App/Sources/Views` | 四态页面、权限页 |
| `App/Sources/Components` | PhotoHeroCard、缩略图条、徽章、进度、结果卡、诊断 |
| `App/Sources/DesignSystem` | 颜色 / 间距 / 字体 / 动效 |
| `App/Sources/AppModel.swift` | 队列、选择、导入、取消、诊断 |
| `App/Sources/Integrations/Shortcuts` | AppIntent 与 AppShortcutsProvider |
| `Services/Sources/LingXiServices` | PhotoKit 适配 + ConversionService |
| `Engine/Sources/LingXiEngine` | URL → URL 固定管线 |
| `Kit/Sources/LingXiKit` | HEIF 解析、兼容性、无损校验、诊断格式化 |
| `Core/Sources/StylePortCore` | vendor 风格核心，尽量不改 |
| `ShareExtension/Sources` | 分享扩展入口与 SwiftUI 流程 |
