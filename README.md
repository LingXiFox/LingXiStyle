# LingXiStyle

给 iPhone 16 / 17 系列 HEIC 原片追加第三代摄影风格（Texture / Grain），另存为一张新的 HEIC。
原图不会被覆盖、不会被转码，照片不离开设备。

![LingXiStyle app icon](App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

> [!IMPORTANT]
> 这是一个源码项目：**不上架 App Store，不提供 TestFlight、预编译 IPA 或侧载包**。
> 你需要 macOS、Xcode 和免费 Apple ID，从源码编译并安装到自己的 iPhone。
> Personal Team 签名 7 天过期，到期重新编译安装即可；相册里的照片不会丢。

## 状态

- 自动化测试：`LingXiKitTests` 10/10、`LingXiEngineTests` 2/2、`StylePortCoreTests` 14（2 个依赖外部 fixture，默认跳过）。
- 真实样张：8064×6048 的 48MP HEIC，54 个主图 tile，11/11 项无损校验通过。
- 主 App 已在一台 iPhone 16 Pro Max 上安装并运行；文件导入的 `iref` 解析问题已修复。
- 分享扩展、快捷指令、12/24MP、权限、存储、取消等系统矩阵尚未逐项验证。
- `generic/platform=iOS` 构建通过，0 error、0 compiler warning。

## 它做什么

- 从系统「照片」选择 HEIC 原片，或从「文件」导入 `.heic` / `.heif`。
- 用 PhotoKit 取出**原始资源文件**（iCloud 原件会真实下载），只追加第三代纹理与颗粒。
- 输出编码后的主图 payload 逐 item 逐块比对 SHA-256；HDR、EXIF、Styles、缩略图保留。
- 用 `PHAssetCreationRequest` 另存为相册中的**新照片**，保存后回读确认仍是 HEIC。
- 提供真实的阶段进度、可取消队列、成功 / 跳过 / 失败统计、中文错误与诊断信息。

## 它不做什么

- 不覆盖原图，不修改原 Asset，不写回原文件。
- 不做 Live Photo 视频、ProRAW、JPEG → HEIC 转码、云端上传。
- 不伪造百分比、不生成虚假的前后对比、不用动画掩盖失败。
- 不使用私有框架，不依赖 App Group。
- 不发布 App Store 版本、IPA 或侧载安装包。

## 环境

| 项 | 版本 / 值 |
| --- | --- |
| 开发环境 | macOS + Xcode 16 或更高（作者使用 Xcode 27.3） |
| 部署目标 | iOS 18.0+ |
| 目标设备 | iPhone 16 / 17 系列 HEIC；其他 HEIC 需自行验证 |
| 工程生成 | [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 |
| 签名 | 你自己的 Apple Development Team；仓库不含 Team ID |
| 第三方依赖 | 仅 Apple 系统框架；无第三方 UI 框架 |

## 快速开始

需要 macOS、Xcode 16+、XcodeGen 2.46+。

```bash
git clone https://github.com/LingXiFox/LingXiStyle.git
cd LingXiStyle
brew install xcodegen
xcodegen generate
open LingXiStyle.xcodeproj
```

在 Xcode 的 Signing & Capabilities 里为 `LingXiStyle` **和 `LingXiStyleShare`** 选择自己的 Team。
如果 Bundle ID 冲突，把 `project.yml` 中的 `com.lingxifox` 全部替换成自己的前缀，再执行
`xcodegen generate`。

连接 iPhone，选择 `LingXiStyle` scheme，Run。首次启动前在
「设置 → 通用 → VPN 与设备管理」信任你的开发证书。主 App 跑通后，再测试随 App 一起安装的分享扩展。

命令行构建：

```bash
xcodebuild -project LingXiStyle.xcodeproj \
  -scheme LingXiStyle \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  -allowProvisioningUpdates build
```

跑测试：

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
```

## 分发方式

这个仓库只提供源码。原因很实际：

1. 目标设备和系统矩阵很窄，HEIC 的 `iref` / grid / tile 结构会随机型和系统版本变化，尚未做完整验证。
2. 预编译 IPA 无法用不同人的签名复用；免费证书 7 天过期，最适合的方式就是自己从源码编译。
3. 「打开相册」使用未公开的 `photos-redirect://`，不把它作为商店分发依赖。

因此仓库不发布 IPA，也不提供 AltStore / 侧载支持。

## 架构

```
App (SwiftUI)                     ShareExtension (SwiftUI in UIKit host)
        \                              /
         \                            /
          LingXiServices  ← 唯一的 ConversionService
                |
          LingXiEngine  (URL → URL，固定管线)
           /        \
      LingXiKit   StylePortCore (vendor，第三代风格编码核心)
```

| 层 | 位置 | 职责 |
| --- | --- | --- |
| App | `App/Sources` | 四态 UI、DesignSystem、AppModel、快捷指令 |
| Services | `Services/Sources/LingXiServices` | PhotoKit 适配 + 唯一转换入口，App 与扩展共用同一份二进制 |
| Engine | `Engine/Sources/LingXiEngine` | 读文件 → 检查 → 调核心 → 复审 → 写临时文件 |
| Kit | `Kit/Sources/LingXiKit` | ISO BMFF / HEIF 解析、兼容性判定、无损校验、诊断 |
| Core | `Core/Sources/StylePortCore` | 上游第三代风格核心（MIT，见 ThirdPartyNotices） |

所有入口（图库、文件导入、快捷指令、分享扩展）最终都调用
`ConversionService.shared.convert(_:onStage:)`。PhotoKit 与分享面板只是输入 / 输出适配器，
不参与编码决策。

### 固定管线

1. `PHAssetResourceManager.writeData` 导出原始资源文件（`isNetworkAccessAllowed = true`）。
2. `HEICInspector` 解析 `ftyp / meta / iinf / iref / iprp / iloc`，判断 grid、tile、HDR、Styles、EXIF、缩略图。
3. `CompatibilityEvaluator` 给出 `ready / alreadyEnhanced / unsupported`，UI 只显示真实结论。
4. `StylePorter.patch` 只追加 Texture / Grain（`analyzePhoto = false`，其余效果关闭）。
5. 重新解析输出，`IntegrityVerifier` 对主图 payload 逐 item 分块 SHA-256 比对，并检查 HDR、EXIF、Styles、缩略图、Gain Map。
6. `PHAssetCreationRequest.addResource(with: .photo, fileURL:)` 另存新 Asset，`originalFilename` 形如 `IMG_1234_TextureGrain.HEIC`。
7. 回读新 Asset 的资源类型，确认仍是 HEIC 才报告成功。

### 无损的定义

- 主图编码 payload：逐 item、逐 tile、排序后分块 SHA-256 完全一致。
- HDR 层、EXIF、Styles / Texture Styles、缩略图、Gain Map 均保留。
- 因为容器里新增了纹理与元数据，整个文件的 SHA-256 必然不同；UI 与诊断不会把它说成「文件完全一致」。

## 兼容性

| 输入 | 结果 |
| --- | --- |
| iPhone 16 / 17 HEIC 原片（含 grid + 多 tile） | 可解锁 |
| 已带第三代 Texture Styles | 无需转换 |
| Live Photo | 暂不支持，跳过并提示；不会处理视频部分 |
| RAW / RAW+HEIC | 暂不支持 |
| JPEG / PNG / TIFF / DNG | 拒绝，并给出中文原因 |
| 已在系统相册编辑过的 Asset | 提示会基于当前原件另存新照片，不覆盖 |
| 损坏 / 缺主图 / 缺 Styles | 拒绝，诊断里保留原始错误码 |

## 四个页面

1. **空状态**：品牌标题、4:5 构图框、主按钮「选择照片」、次级「从文件导入」、隐私文案「仅在本机处理 · 原图始终保留」。
2. **已选照片**：大图不裁切、60–72pt 缩略图条、兼容标签、数量与主 CTA。
3. **转换中**：照片始终清晰，只有边框层承载扫光 / 呼吸光；真实阶段文字与 X/Y；可取消队列。
4. **结果页**：成功 / 跳过 / 失败数量、「已保存新照片」、打开相册、失败原因、重试与诊断。

支持真深 / 浅色、Dynamic Type、横竖屏、Reduce Motion（关闭循环光、扫边与缩放，只保留状态变化）。
设计令牌见 `App/Sources/DesignSystem/Tokens.swift`，动效见 `Motion.swift`。

## 快捷指令

「解锁第三代摄影风格」接受 1–N 个文件，参数：

- 保存到相册（默认开）
- 返回转换后的文件（默认关）
- 仅检查兼容性（默认关）

输出转换后的文件列表（仅在打开「返回转换后的文件」时），并用「已转换 / 已存入相册 /
跳过 / 失败」分项统计。输入会先复制到 App 沙盒，再交给 `ConversionService`，不会碰原文件。

## 分享扩展

在系统「照片」里分享一张 HEIC 到「补质感」：

1. `loadFileRepresentation` 后**立刻**复制到扩展自己的沙盒（回调外 URL 会失效）。
2. 强制解析并校验完整 HEIC；不是 HEIC 就提示「请在 LingXiStyle 内从图库选择照片」。
3. 通过后调用同一个 `ConversionService` 保存新照片。

分享面板有时只给 JPEG / 预览图，这时会被拒绝，这是预期行为——转码会破坏原始编码。

## 错误码

| 码 | 含义 |
| --- | --- |
| `E_UNREADABLE` | 文件不可读 |
| `E_CORRUPT` | HEIF 结构无法解析 |
| `E_UNSUPPORTED:<issues>` | 兼容性判定拒绝，issues 为具体项 |
| `E_ALREADY_TEXTURED` | 已带第三代质感 |
| `E_ENGINE` | 核心编码错误 |
| `E_VERIFY:<checks>` | 无损校验失败 |
| `E_WRITE` | 临时文件写入失败 |
| `E_PHOTO_NO_HEIC` | 该 Asset 没有 HEIC 照片资源 |
| `E_PHOTO_EXPORT` | 原件导出失败 |
| `E_PHOTO_SAVE` | 相册写入失败 |
| `E_PHOTO_SAVED_MISSING` | 保存后找不到新 Asset |
| `E_PHOTO_SAVED_NOT_HEIC` | 保存后回读不是 HEIC |

诊断页会附上文件结构、item 布局、校验结果与脱敏后的系统信息；原始码只出现在诊断里，
主界面只显示中文解释。

## 目录

```
App/Sources/            Views / Components / DesignSystem / Models / Integrations / AppModel.swift
Services/Sources/       LingXiServices（PhotoKit 适配 + ConversionService）
Engine/Sources/         LingXiEngine
Kit/Sources/            LingXiKit
Core/Sources/           StylePortCore（vendor）
Core/Resources/Profiles 45-15 / 48-12 / live-photo-video
Kit/Tests/              ISOBox / 兼容性 / 校验测试
Engine/Tests/           引擎集成测试
ShareExtension/         分享扩展
ThirdPartyNotices/      上游 MIT 许可证与 vendor 说明
project.yml             XcodeGen 工程定义
```

## 已知限制

- 主 App 已在真机上运行；分享扩展、快捷指令，以及 12/24MP、权限、存储、取消等系统矩阵尚未逐项验证。详见 [TEST_REPORT.md](TEST_REPORT.md)。
- 不同机型 / iOS 版本的 HEIC 可能使用不同的 `iref` 结构；已加 16-bit / 32-bit 回归测试，但仍需更多样本。
- 「打开相册」使用未公开的 `photos-redirect://`，失败会回退到系统设置；这是体验优化，不影响保存结果。
- 分享扩展首次运行时可能拿不到相册写入授权（扩展内不一定能弹权限框）。此时会提示先回 App 授权；这是系统行为，需真机确认具体表现。
- 分享面板可能把照片转成 JPEG，扩展会拒绝而不是偷偷转码。
- Live Photo 暂不支持，会跳过并提示；视频部分不会被处理。
- 免费 Personal Team 签名 7 天过期。

## 隐私

- App 本身不发起网络请求，不上传照片，不收集分析数据。
- iCloud 原件下载由 PhotoKit 在系统层完成。
- 导出与转换的临时文件位于沙盒 `tmp`，每个任务结束即删除；成功保存的照片由系统相册管理。

## 第三方与许可

- 本项目：[MIT License](LICENSE)，Copyright (c) 2026 LingXiFox。
- 风格核心：[Shalielie](https://github.com/nathanatgit/Shalielie)，MIT License，Copyright (c) 2026 nathanatgit；全文见 [ThirdPartyNotices/Shalielie-LICENSE.txt](ThirdPartyNotices/Shalielie-LICENSE.txt)，vendor 范围见 [ThirdPartyNotices/README.md](ThirdPartyNotices/README.md)。
- 界面只使用 SF Symbols、系统字体与原生材质；SF Symbols 不随本仓库分发。
- Apple、iPhone、PhotoKit 等是 Apple Inc. 的商标。本项目与 Apple 无关联。

## 文档

- [TEST_REPORT.md](TEST_REPORT.md)：构建、测试、真机验证与未覆盖矩阵。
- [AGENTS.md](AGENTS.md)：给在本仓库工作的编码代理的约束。
