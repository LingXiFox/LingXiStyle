# 1.9.1 P1 研究记录：第二代摄影风格 × 第三代纹理与颗粒

- 状态：研究完成，结论为「不集成」，不阻塞 1.9.1 发布
- 范围：iPhone 16 引入的第二代摄影风格（Photographic Styles，iOS 18）与 iPhone 17 引入的
  纹理 / 颗粒（Texture / Grain，`texture_styles`）之间的关系
- 验证条件：本机无真机、无 iPhone 16 / 17 实拍样张库；以下结论来自现有代码路径、HEIF 元数据
  结构与本机 48MP 样张的检查结果，属于设计层结论，**不是**真实样本实验结论

## 问题

191.md 希望研究：能否让带第二代摄影风格的照片，在纹粒里获得第三代纹理 / 颗粒编辑？
如果不可靠，就独立记录，不影响发布。

## 已知事实（仓库内可验证）

1. 纹粒写入的是 Apple 私有元数据条目
   `tag:apple.com,2026:photo:metadata:texture_styles`（`Kit/Sources/LingXiKit/HEICInspection.swift:101`），
   由 `StylePorter` 在 HEIF 容器内新增 item，不重编码主图 payload。
2. `HEICInspector` 区分三件事（`HEICInspection.swift`）：
   - `hasStyleMetadata`：文件带摄影风格相关元数据；
   - `hasTextureStyle`：文件已带 `texture_styles` 条目（纹粒或系统已加过质感）；
   - `hasExif` / `hasHDRGainMap` / `hasThumbnail`：需要原样保留的其它层。
3. `CompatibilityEvaluator` 只把 `hasTextureStyle` 判为「已带纹理与颗粒」
   （`Kit/Sources/LingXiKit/Compatibility.swift:131`），**带第二代摄影风格的照片不会被拒绝**，
   会正常追加纹理与颗粒。这一点 1.8.1 以来未变。
4. `IntegrityVerifier` 在转换后检查 `texture_styles` 条目是否从无到有
   （`IntegrityVerifier.swift:74-75`），并逐 item 比对主图 payload，因此风格元数据作为容器元数据
   会随主图一起保留。

## 关键判断

第二代摄影风格与第三代纹理 / 颗粒不是同一层东西：

- 摄影风格是「影调映射参数 + 参考图」的语义描述，由系统渲染管线在显示 / 导出时解释；
  文件里保存的是 Apple 私有的风格参数，不是可直接编辑的纹理图层。
- 第三代纹理 / 颗粒是 `texture_styles` 条目描述的一套质感参数，同样由系统解释，但纹粒只做
  「追加条目」这一件事，不解析也不合成风格参数。
- 两者都依赖系统私有解释器，Apple 没有公开读写 API。没有公开 API 就无法把「第二代风格参数」
  可靠地映射成「第三代纹理强度 / 颗粒大小」，任何映射都只能靠逆向试错。

因此本项目**不实现**「第二代风格 → 第三代纹理」的转换：

- 不做参数猜测。错误的映射会产出看起来像质感、实际不可控的结果，违背「不伪造效果」的约束。
- 不修改、不删除原文件的风格元数据。带风格的照片照常转换，风格与新增质感共存，由系统决定
  如何叠加显示。
- 不把「文件里有 style 元数据」当成「已带质感」而拒绝；只有真正的 `texture_styles` 才算已处理。

## 对用户可见行为的影响

| 输入 | 1.9.1 行为 |
| --- | --- |
| 第二代摄影风格照片（无 texture_styles） | 可添加纹理与颗粒；风格元数据原样保留 |
| 已带 texture_styles（纹粒或系统质感） | 判为「无需处理」，不重复叠加 |
| 风格 + 已带质感 | 同上，判为无需处理 |
| 无法解析风格元数据 | 不影响转换；诊断里只显示 style 标志位，不输出私有字段内容 |

## 仍未验证 / 后续

- 需要在 iPhone 16（iOS 18）与 iPhone 17（iOS 26+）上各取一组真实样本，确认：
  1. 带摄影风格的照片经纹粒转换后，系统「照片」里风格与质感是否同时生效；
  2. `hasStyleMetadata` 在不同系统版本下的检出率；
  3. 系统后续版本是否公开纹理参数的读写接口。
- 上述验证需要真机与授权样本；本机没有真机，故 1.9.1 不宣称已支持「风格到质感」的转换。
- 若未来 Apple 公开 API，可在 `StylePorter` 外新增一层参数映射，仍保持「不重编码主图」的约束。
