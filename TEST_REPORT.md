# TEST_REPORT

- 日期：2026-11-06
- 项目：LingXiStyle 1.0.0（build 1）
- 结论：**工程可编译、自动化测试通过；真实 8064×6048 HEIC 的引擎转换与 11 项无损校验已跑通；主 App 已在真机上运行；分享扩展、快捷指令与完整系统矩阵仍待验证。**

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.3（26C5035r），Apple Silicon |
| Xcode | 27.3（27C5020n），MacOSX27.3.sdk |
| Swift | Swift 5 语言模式（`SWIFT_VERSION=5.0`） |
| 部署目标 | iOS 18.0 |
| 签名 | 自动签名；使用开发者自己的 Apple Development Team（仓库不包含 Team ID） |
| 模拟器 | **无可用 iOS runtime**（`xcrun simctl list runtimes` 为空），未做 UI 运行验证 |

## 2. 构建结果

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates build
```

结果：**BUILD SUCCEEDED**，0 error、0 compiler warning。构建日志另有 1 条系统工具提示
`Metadata extraction skipped, no AppIntents.framework dependency found`，来自
`LingXiServices` framework 的 App Intents 元数据扫描；该 framework 不包含快捷指令，
不影响 App 的 `Metadata.appintents` 生成，也不影响构建或运行。

产物包含：

- `LingXiStyle.app`（含 `Assets.car`、`AppIcon60x60@2x.png`、`CFBundleIconName=AppIcon`）
- `PlugIns/LingXiStyleShare.appex`
- 嵌入的 `LingXiKit.framework` / `LingXiEngine.framework` / `LingXiServices.framework` / `StylePortCore.framework`
- `Metadata.appintents`（快捷指令已编译进 App）

分享扩展与主 App 均使用同一个 `LingXiServices` framework，不存在两份 ConversionService 实现。

### 真机安装记录

2026-11-06 用 `xcrun devicectl device install app` 将签名产物安装到已配对的
iPhone 16 Pro Max 成功。首次启动被系统拒绝，原因是免费开发者证书尚未在设备上被显式信任；
在「设置 → 通用 → VPN 与设备管理」信任本机开发证书后，`process launch` 成功。
当前设备上安装的是包含 `iref` 修复的最新构建。重装后自动启动因设备锁屏被系统拒绝
（`Locked`），解锁后手动打开即可；证书信任后的启动此前已验证成功。
机主确认 `iref` 修复后的主 App 文件导入与主流程正常；没有保留逐步 UI 操作日志。

### 真实 HEIC 引擎验证

用一张 8064 × 6048（48MP）的 iPhone 实拍 HEIC（125 items、54 个主图 tile、
15 个 HDR gain-map tile）验证：

- 修复 `iref` 子 box 解析后，兼容性判定从「缺少主图分块数据」变为「可解锁」。
- `ConversionEngine.convert` 返回 `mode=add-texture`；输出 5,933,004 字节，
  `texture=added #151 -> [55, 80], 12 2026 mattes`。
- 重新解析输出：主图 54 tiles、HDR 15 tiles、style / EXIF / thumbnail / gain map 全保留，
  `texture=true`。
- `IntegrityVerifier` 11/11 项通过。
- 用 `sips` 解码原图与输出的 1200px 预览，像素 SHA-256 完全一致（纹理是元数据，
  不重编码主图 payload）。
- 对输出再次判定为「已有第三代质感」，不会重复处理。

## 3. 自动化测试

| Scheme | 结果 | 用例数 | 失败 | 跳过 |
| --- | --- | --- | --- | --- |
| `LingXiKitTests` | TEST SUCCEEDED | 10 | 0 | 0 |
| `LingXiEngineTests` | TEST SUCCEEDED | 2 | 0 | 0 |
| `StylePortCoreTests` | TEST SUCCEEDED | 14 | 0 | 2 |

覆盖内容：

- `ISOBoxTests`：ISO BMFF 同级 box 解析、尾部填充容忍。
- `HEIFReferenceTests`：`iref` 子 box 的 16-bit / 32-bit ID 解析；损坏条目只产生 warning，不崩溃。
- `CompatibilityTests`：完整 HEIC 可解锁；已编辑资产仍可转换（提示交给 UI）；Live Photo 拒绝；
  已带第三代质感不重复处理；非 HEIF 只报容器问题。
- `EngineTests`：JPEG 输入必须拒绝且错误码为 `E_UNSUPPORTED:notHEIC`；输出名稳定为
  `IMG_0001_TextureGrain.heic`，重复处理不会叠加后缀。
- `StylePortCoreTests`：上游编码核心的 14 项结构测试（2 项依赖 `STYLEPORT_FIXTURES` / `STYLEPORT_LIVE_VIDEO` 环境变量，未配置所以跳过）。

命令均可复现：

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
```

### 自动化测试盖不到的部分

- PhotoKit 权限、iCloud 下载、相册保存回读、分享扩展授权等系统交互。
- App 内的完整点击链路与四态 UI 的深浅色、Dynamic Type、Reduce Motion、VoiceOver 表现。
- 12MP / 24MP、夜景、人像、Live Photo、RAW 等多场景真机样张。
- 第三代质感在系统「照片」中的实际视觉呈现（`addTexture` 写的是元数据，`sips` 解码
  不能证明系统相册的渲染效果）。

## 4. 真机测试矩阵

状态说明：⚪ 未执行（真实 HEIC 的引擎转换已验证，主 App 主流程已由机主确认；
分享扩展、快捷指令、系统权限 / 存储与多数 UI 场景仍未跑完整矩阵；无模拟器 runtime）；✅ 已验证。

| # | 场景 | 预期 | 状态 |
| --- | --- | --- | --- |
| 1 | 12MP HEIC 原片 | 成功，另存新照片，原图不变 | ⚪ |
| 2 | 24MP HEIC 原片 | 成功 | ⚪ |
| 3 | 48MP Pro 原片（多 tile grid） | 成功，逐 tile 无损 | ✅ 引擎层（54 tiles，11/11 校验） |
| 4 | HDR / Gain Map 照片 | 成功，HDR 元数据保留 | ✅ 引擎层（15 个 gain-map tiles 保留） |
| 5 | 夜景 / 人像 | 成功，纹理只追加不替换 | ⚪ |
| 6 | 已含第三代质感 | 「无需转换」，不写入相册 | ✅ 自动化（重复输出判定 alreadyEnhanced） |
| 7 | Live Photo | 跳过并提示暂不支持，不处理视频 | ✅ 自动化（CompatibilityTests） |
| 8 | JPEG | 拒绝，中文原因 | ✅ 引擎层已测 |
| 9 | PNG / TIFF / DNG | 拒绝 | ⚪ |
| 10 | RAW / RAW+HEIC | 「暂不支持」 | ⚪ |
| 11 | 已在相册编辑过的 Asset | 提示基于当前原件另存，不覆盖 | ⚪ |
| 12 | iCloud 原件未下载 | 显示「正在下载原件」，完成后继续 | ⚪ |
| 13 | 分享面板返回 JPEG | 扩展拒绝并提示回 App 选图 | ⚪ |
| 14 | PhotosPicker 返回 JPEG | 拒绝并提示 | ⚪ |
| 15 | 相册权限「受限」 | 只显示可访问照片，流程可用 | ⚪ |
| 16 | 相册写入权限拒绝 | 中文提示 + 诊断码 | ⚪ |
| 17 | 存储空间不足 | 失败并说明原因，不产生半张照片 | ⚪ |
| 18 | 批量转换中取消 | 当前张完成后停止，不再开新张；已保存保留 | ⚪ |
| 19 | 重试失败项 | 只重转失败项，不重复保存已成功项 | ⚪（代码已加 outcome 守卫） |
| 20 | 深色 / 浅色 | 真动态色，对比度 ≥ 4.5:1 | ⚪ |
| 21 | Dynamic Type 大字号 | 布局不截断，主按钮仍可点 | ⚪ |
| 22 | Reduce Motion | 关闭扫光 / 呼吸光 / 缩放 | ⚪ |
| 23 | VoiceOver | 大图、缩略图、进度、错误可读 | ⚪ |
| 24 | 快捷指令（保存 / 返回文件 / 仅检查） | 统计正确，文件可回传 | ⚪（已编译） |
| 25 | 分享扩展完整闭环 | 保存新照片，失败有中文提示 | ⚪（已编译） |
| 26 | 7 天签名过期 | 重新安装后可继续使用，照片不丢 | ⚪ |

## 5. 项目书要求对照

| 要求 | 状态 |
| --- | --- |
| 读 PhotoKit 原始 HEIC，不经 UIImage 转码 | ✅ 代码路径审查通过 |
| 只追加 Texture / Grain | ✅ 参数固定 `analyzePhoto:false`，其余效果关闭 |
| 另存新照片、不覆盖 | ✅ `PHAssetCreationRequest` + 回读 HEIC |
| 无损校验（主图 payload 逐 item SHA-256） | ✅ 真实 48MP 样本 11/11 通过 |
| 四页面、真实阶段、可取消队列 | ✅ 主 App 实机运行；四态 UI 未逐项验收 |
| 真深 / 浅色、Dynamic Type、Reduce Motion | ✅ 令牌与预览齐全，待真机目视 |
| 分享扩展 + 快捷指令 | ✅ 编译通过，待真机闭环 |
| 无第三方 UI 框架 | ✅ 仅系统框架 |
| 文档 / 许可证 / 构建命令 | ✅ README、AGENTS、本报告、ThirdPartyNotices |

## 6. 已知风险

1. **最大的未覆盖项是分享扩展、快捷指令与系统矩阵。** 引擎已对 48MP 实拍 HEIC 跑通
   `addTexture` 与 11 项无损校验；主 App 主流程已由机主确认；分享扩展、快捷指令、权限、
   存储、取消和多机型场景还没有逐项完成。
2. 不同机型 / iOS 版本的 HEIC 可能使用不同的 `iref` 结构；已加 16-bit / 32-bit 回归测试，
   但仍需多机型样本。
3. 分享扩展内请求相册写入权限的行为依赖系统；若扩展不能弹权限框，会提示先回 App 授权。
4. `photos-redirect://` 是未公开 scheme，「打开相册」失败会回退系统设置。
5. `StylePortCoreTests` 有 2 项跳过，因为未设置 `STYLEPORT_FIXTURES` / `STYLEPORT_LIVE_VIDEO`，不是代码失败。
6. 免费 Personal Team 签名 7 天过期，属预期限制。

## 7. 复现与验收建议

真机验收顺序：

1. 用 Xcode 安装主 App，授予「照片」读取与添加权限。
2. 选 1 张 iPhone 16/17 拍摄的 HEIC，确认兼容标签为「可解锁」。
3. 转换，确认结果页显示「已保存新照片」；到系统「照片」检查新 Asset 可编辑、可再次保存。
4. 对比原图与新图：构图、HDR、EXIF、缩略图应一致，仅纹理 / 颗粒变化。
5. 再测批量 3 张 + 取消、已含第三代、Live Photo、JPEG 拒绝。
6. 最后安装分享扩展与快捷指令，各跑一次闭环。
