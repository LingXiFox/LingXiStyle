# TEST_REPORT

- 日期：2026-11-07
- 项目：LingXiStyle 1.1.0（build 2）
- 结论：**XcodeGen 生成、Debug / Release 构建与全部自动化测试通过；1.0 的 48MP 真实 HEIC 引擎验证仍有效。1.1 的任务生命周期、分享扩展、图片加载、批量并发、真实进度、按需权限与 UI 升级已完成代码与编译验证；当前环境没有 iOS 模拟器 runtime，1.1 UI、分享扩展、快捷指令与系统权限矩阵仍需真机验收。**

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.3（26C5035r），Apple Silicon |
| Xcode | 27.3（27C5020n），MacOSX27.3.sdk |
| Swift | Swift 5 语言模式（`SWIFT_VERSION=5.0`） |
| 部署目标 | iOS 18.0 |
| 签名 | 自动签名；使用开发者自己的 Apple Development Team（仓库不包含 Team ID） |
| 模拟器 | **无可用 iOS runtime**（`xcrun simctl list runtimes` 为空），未做 UI 运行、截图与 VoiceOver 验收 |
| 真机 | 1.0 曾在 iPhone 16 Pro Max 安装运行；1.1 未做真机安装 |

## 2. 构建结果

### 2.1 工程生成

`xcodegen generate` 成功，生成 `LingXiStyle.xcodeproj`。版本已从 1.0.0 / build 1 升至
**1.1.0 / build 2**，App 与 ShareExtension 的 Info.plist 均使用 `$(MARKETING_VERSION)` /
`$(CURRENT_PROJECT_VERSION)`。

### 2.2 Debug 与 Release

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiStyle \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

结果：**Debug BUILD SUCCEEDED；Release BUILD SUCCEEDED**，0 error、0 Swift compiler warning。

Release 日志另有 4 条系统工具提示
`Metadata extraction skipped, no AppIntents.framework dependency found`，来自
`appintentsmetadataprocessor` 扫描不含快捷指令的 framework；不是 Swift 编译警告，
不影响 App 的 `Metadata.appintents` 生成，也不影响构建或运行。

产物包含：

- `LingXiStyle.app`（含 `Assets.car`、`AppIcon60x60@2x.png`、`CFBundleIconName=AppIcon`）
- `PlugIns/LingXiStyleShare.appex`
- 嵌入的 `LingXiKit.framework` / `LingXiEngine.framework` / `LingXiServices.framework` / `StylePortCore.framework`
- `Metadata.appintents`（快捷指令已编译进 App）

分享扩展与主 App 均使用同一个 `LingXiServices` framework，不存在两份 ConversionService 实现。

### 2.3 真机安装记录（1.0 基线）

2026-11-06 用 `xcrun devicectl device install app` 将 1.0 签名产物安装到已配对的
iPhone 16 Pro Max 成功。首次启动被系统拒绝，原因是免费开发者证书尚未在设备上被显式信任；
在「设置 → 通用 → VPN 与设备管理」信任本机开发证书后，`process launch` 成功。
机主确认 1.0 的文件导入与主流程正常；没有保留逐步 UI 操作日志。

**该记录不能作为 1.1 真机通过的依据。** 1.1 的页面、分享扩展、快捷指令、权限与取消流程均未在本轮真机验证。

### 2.4 真实 HEIC 引擎验证（1.0 基线，1.1 未改算法）

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

1.1 没有修改 `StylePortCore` 的纹理 / 颗粒算法，也没有改变固定转换管线；上述结果作为
引擎基线保留。

## 3. 自动化测试

| Scheme | 结果 | 用例数 | 失败 | 跳过 |
| --- | --- | --- | --- | --- |
| `LingXiKitTests` | TEST SUCCEEDED | 16 | 0 | 0 |
| `LingXiEngineTests` | TEST SUCCEEDED | 2 | 0 | 0 |
| `StylePortCoreTests` | TEST SUCCEEDED | 14 | 0 | 2 |

命令均可复现：

```bash
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiKitTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme LingXiEngineTests \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project LingXiStyle.xcodeproj -scheme StylePortCoreTests \
  -destination 'platform=macOS,arch=arm64' test
```

覆盖内容：

- `ISOBoxTests`：ISO BMFF 同级 box 解析、尾部填充容忍。
- `HEIFReferenceTests`：`iref` 子 box 的 16-bit / 32-bit ID 解析；损坏条目只产生 warning，不崩溃。
- `CompatibilityTests`：完整 HEIC 可解锁；已编辑资产仍可转换（提示交给 UI）；Live Photo 拒绝；
  已带第三代质感不重复处理；非 HEIF 只报容器问题。
- `ConversionRunTests`（1.1 新增 6 项）：
  - 已保存项不会被再次转换；
  - 取消后保留已完成项，剩余项按顺序取消；
  - 未开始就取消时，队列按顺序产生取消动作；
  - 旧 session token 不能完成新会话；
  - unsupported / unavailable 不阻塞后续可转换项；
  - 非 pending 项的完成回调被忽略，防止旧回调覆盖新状态。
- `EngineTests`：JPEG 输入必须拒绝且错误码为 `E_UNSUPPORTED:notHEIC`；输出名稳定为
  `IMG_0001_TextureGrain.heic`，重复处理不会叠加后缀。
- `StylePortCoreTests`：上游编码核心的 14 项结构测试（2 项依赖 `STYLEPORT_FIXTURES` /
  `STYLEPORT_LIVE_VIDEO` 环境变量，未配置所以跳过）。

### 自动化测试盖不到的部分

- PhotoKit 权限、iCloud 下载、相册保存回读、分享扩展授权等系统交互。
- App 内的完整点击链路与四态 UI 的深浅色、Dynamic Type、Reduce Motion、VoiceOver 表现。
- 12MP / 24MP、夜景、人像、Live Photo、RAW 等多场景真机样张。
- 第三代质感在系统「照片」中的实际视觉呈现（`addTexture` 写的是元数据，`sips` 解码
  不能证明系统相册的渲染效果）。
- 内存峰值、真实临时文件清理时机、长时间批量任务；本轮只做代码路径审查，未用 Instruments 测量。

## 4. 1.1 静态与行为验证

以下项目通过**编译、单元测试或代码审查**确认，不代表真机运行通过：

| 项 | 验证方式 | 结论 |
| --- | --- | --- |
| 任务会话隔离 | `ConversionRunTests` + AppModel 代码审查 | 旧 stage / result 回调有 session token guard；旧 beginConversion 有 startToken guard |
| 取消保留已保存项 | `ConversionRunTests` + 保存边界审查 | 已写入相册的保留；未开始项转 cancelled；保存开始后不强行中断 |
| reset 不删除在用文件 | SessionWorkspace 引用计数审查 | reset 只 retire，最后一个活跃操作结束才删除 |
| 重试不重复保存 | `ConversionRunTests` + 保存回读审查 | 只重置 failed；saved 跳过；权限 / 工作区未就绪时保留失败状态，不提前清空；回读失败记录 warning 而非 failed |
| 分享扩展状态机 | 编译 + 代码审查 | 处理中只显示取消；成功才显示完成；失败 / 取消可重试；关闭等待安全边界 |
| 移除 `photos-redirect://` | 全仓库检索 | 0 处引用；结果页改为应用内预览 + ShareLink |
| 图片加载忽略降级图 | PhotoLibraryService 审查 | degraded 回调被忽略；处理 error / cancelled；支持取消 |
| 批量准备并发 | AppModel 审查 | `withBoundedConcurrency(limit: 2)`，保持输入顺序 |
| 真实保存阶段 | ConversionService 审查 | 保存前发 `.saving`，成功后发 `.finished`；无定时器 / 假百分比 |
| iCloud 下载进度 | PhotoLibraryService 审查 | 使用 `PHAssetResourceRequestOptions.progressHandler` |
| 按需权限 | AppModel 审查 | 启动不请求；选图后请求 read；保存前请求 addOnly；文件导入不需要相册权限 |
| 快捷指令输出文件 | UnlockTextureIntent 审查 | `IntentFile` 用内存 data，避免临时目录删除后失效 |
| Reduce Motion | 组件审查 | 循环光、扫边、缩放均受环境值控制 |
| UI 预览 | PreviewSupport 编译 | 覆盖空状态、单选、多选、下载、转换、保存、成功、部分失败、警告、权限、深浅色、大字体、Reduce Motion |

## 5. 真机测试矩阵

状态说明：✅ 已验证（自动化 / 引擎层）；🟡 已实现并通过编译，未真机运行；
⚪ 未执行。当前没有 iOS 模拟器 runtime，UI 相关项不能以构建通过替代。

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
| 12 | iCloud 原件未下载 | 显示真实下载进度，完成后继续 | 🟡 已接 progressHandler，未真机 |
| 13 | 分享面板返回 JPEG | 扩展拒绝并提示回 App 选图 | 🟡 已实现，未真机 |
| 14 | PhotosPicker 返回 JPEG | 拒绝并提示 | ⚪ |
| 15 | 相册权限「受限」 | 只显示可访问照片，流程可用 | ⚪ |
| 16 | 相册写入权限拒绝 | 中文提示 + `E_PHOTO_ADD_DENIED` | 🟡 已实现，未真机 |
| 17 | 存储空间不足 | 失败并说明原因，不产生半张照片 | ⚪ |
| 18 | 批量转换中取消 | 当前张到安全边界；已保存保留；未开始取消 | 🟡 状态机自动化通过，未真机 |
| 19 | 重试失败项 | 只重转失败项，不重复保存已成功项 | 🟡 ConversionRun 自动化通过，未真机 |
| 20 | 深色 / 浅色 | 真动态色，对比度 ≥ 4.5:1 | 🟡 代码与预览，未运行 |
| 21 | Dynamic Type 大字号 | 布局不截断，主按钮仍可点 | 🟡 代码与预览，未运行 |
| 22 | Reduce Motion | 关闭扫光 / 呼吸光 / 缩放 | 🟡 代码审查，未运行 |
| 23 | VoiceOver | 大图、缩略图、进度、错误可读 | ⚪ 未运行 |
| 24 | 快捷指令（保存 / 返回文件 / 仅检查） | 统计正确，文件可回传 | 🟡 已修复文件生命周期，未真机 |
| 25 | 分享扩展完整闭环 | 保存新照片，失败有中文提示 | 🟡 已重写并编译，未真机 |
| 26 | 7 天签名过期 | 重新安装后可继续使用，照片不丢 | ⚪ |

## 6. 1.1 要求对照

| 要求 | 状态 |
| --- | --- |
| P0-1 任务生命周期、取消、重试、防止旧任务覆盖 | ✅ 会话状态机 + 6 项单测；真机未验 |
| P0-2 分享扩展取消 / 完成 / 重试 / 临时文件 | 🟡 已重写并编译；真机未验 |
| P0-3 移除 `photos-redirect://` | ✅ 全仓库 0 引用；应用内预览 + ShareLink |
| P1-1 图片加载处理 degraded / error / cancel | ✅ 代码审查；真机未验 |
| P1-2 批量准备有界并发 2、保持顺序 | ✅ 代码审查；真机未验 |
| P1-3 `.saving` / 真实保存阶段与 iCloud 进度 | ✅ 代码审查；真机未验 |
| P1-4 按需权限 | ✅ 代码审查；真机未验 |
| P2 四页视觉升级、真实阶段动效 | 🟡 编译与预览；无运行时目视验收 |
| 浅 / 深色、Dynamic Type、VoiceOver、Reduce Motion、横竖屏 | 🟡 令牌 / 预览 / 代码；未运行 |
| 保持 HEIC 原始 payload、HDR、EXIF、Styles | ✅ 1.0 真实 48MP 引擎验证；1.1 未改算法 |
| 不引入第三方依赖 / 私有 API | ✅ 仅系统框架；`photos-redirect` 已移除 |
| XcodeGen 可生成、Debug / Release 可构建 | ✅ 本轮实测 |

## 7. 已知风险

1. **最大未覆盖项是 1.1 的真机运行验收。** 当前无 iOS 模拟器 runtime，四页 UI、动效、
   Dynamic Type、VoiceOver、横竖屏与窄屏布局都只有编译和代码审查，没有运行截图。
2. **分享扩展与快捷指令未跑闭环。** 扩展内相册写入授权、`loadFileRepresentation` 实际
   返回格式、`IntentFile` 回传都需要真机确认。
3. **iCloud 下载与取消只在代码层接通。** `progressHandler` 与 `PHAssetResource` 取消行为
   受系统版本影响，需真机观察。
4. 不同机型 / iOS 版本的 HEIC 可能使用不同的 `iref` 结构；已加 16-bit / 32-bit 回归测试，
   但仍需多机型样本。
5. `StylePortCoreTests` 有 2 项跳过，因为未设置 `STYLEPORT_FIXTURES` /
   `STYLEPORT_LIVE_VIDEO`，不是代码失败。
6. 免费 Personal Team 签名 7 天过期，属预期限制。
7. 结果页不再跳转系统「照片」，只提供应用内预览与分享；这是移除未公开 scheme 后的产品取舍。

## 8. 建议的真机验收顺序

1. 用 Xcode 安装 1.1 主 App，首次启动确认不弹相册权限；从「文件」导入一张 HEIC，确认无需权限即可预览。
2. 从系统相册选 1 张 HEIC，确认此时才请求读取权限；兼容标签为「可解锁」。
3. 转换，观察读取 / 检查 / 追加 / 校验 / 保存五个真实阶段；确认照片内容不变，动效只在边框与背景。
4. 结果页查看已保存预览、分享真实 HEIC、继续处理；到系统「照片」确认新 Asset 未被覆盖。
5. 取消一次批量任务：确认已保存照片保留、未开始项取消、重试不重复写入。
6. 用一张 iCloud 未下载原片，观察真实下载进度与取消。
7. 拒绝相册写入权限，确认中文提示与 `E_PHOTO_ADD_DENIED` 只在诊断出现；恢复权限后重试。
8. 测已含第三代、Live Photo、JPEG、RAW；确认提示与跳过统计。
9. 最后测分享扩展（处理中取消 / 失败重试 / 成功完成）与快捷指令三个参数。
10. 在浅色 / 深色、最大 Dynamic Type、Reduce Motion、VoiceOver、横竖屏下各走一遍四页。
