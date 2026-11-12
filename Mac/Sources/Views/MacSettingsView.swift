import AppKit
import SwiftUI
import LingXiKit

struct MacSettingsView: View {
    @ObservedObject var model: MacModel
    @State private var isExportFolderPresented = false

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.9.1"
        let build = info?["CFBundleVersion"] as? String ?? "11"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section(String(localized: "转换", defaultValue: "转换")) {
                LabeledContent(String(localized: "导出文件夹", defaultValue: "导出文件夹")) {
                    HStack(spacing: MacSpacing.xs) {
                        Text(model.exportFolder?.path ?? String(localized: "尚未选择", defaultValue: "尚未选择"))
                            .font(MacType.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(String(localized: "更改…", defaultValue: "更改…")) {
                            isExportFolderPresented = true
                        }
                    }
                }
                Picker(String(localized: "实况照片", defaultValue: "实况照片"),
                       selection: Binding(get: { model.livePhotoMode },
                                          set: { model.setLivePhotoMode($0) })) {
                    ForEach(LivePhotoProcessingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(LivePhotoProcessingMode.quotaNote)
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.textSecondary)
                Text(String(localized: "mac.settings.styleNote",
                            defaultValue: "从「照片」导出的文件如果已经应用了摄影风格，纹粒会在检查阶段提示，不会强行改写。"))
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.textSecondary)
            }

            Section(String(localized: "成果与记录", defaultValue: "成果与记录")) {
                Picker(String(localized: "保险箱保留", defaultValue: "保险箱保留"),
                       selection: Binding(get: { model.vaultRetention },
                                          set: { model.setRetention($0) })) {
                    ForEach(VaultRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
                LabeledContent(String(localized: "当前占用", defaultValue: "当前占用"),
                               value: MacModel.byteText(model.vaultByteCount))
                HStack {
                    Button(String(localized: "清理过期成果", defaultValue: "清理过期成果")) {
                        model.purgeExpired()
                    }
                    Spacer()
                }
            }

            Section(Brand.proName) {
                LabeledContent(String(localized: "当前权益", defaultValue: "当前权益"),
                               value: accessText)
                if model.quota.isPro {
                    if model.purchases.access.source == .subscription {
                        Button(String(localized: "管理订阅", defaultValue: "管理订阅")) {
                            NSWorkspace.shared.open(PurchaseManager.manageSubscriptionsURL)
                        }
                    }
                } else {
                    Button(String(localized: "查看 Pro 方案", defaultValue: "查看 Pro 方案")) {
                        model.isPurchasePresented = true
                    }
                    if model.purchases.trialState.isActive(at: Date()) {
                        Text(String(localized: "24 小时体验进行中，到期后回到免费额度。",
                                    defaultValue: "24 小时体验进行中，到期后回到免费额度。"))
                            .font(MacType.caption)
                            .foregroundStyle(MacPalette.textSecondary)
                    }
                }
                Button(String(localized: "恢复购买", defaultValue: "恢复购买")) {
                    Task { await model.restore() }
                }
                .disabled(model.purchases.isRestoring)
            }

            Section(String(localized: "关于", defaultValue: "关于")) {
                LabeledContent(String(localized: "版本", defaultValue: "版本"), value: versionText)
                Text(Brand.signature)
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.textSecondary)
                Text(String(localized: "mac.settings.privacy",
                            defaultValue: "照片只在本机处理：不上传、不转码、不覆盖原片。保险箱与任务记录保存在本机的应用数据目录。"))
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.textSecondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isExportFolderPresented,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.setExportFolder(url)
            }
        }
    }

    private var accessText: String {
        let access = model.purchases.access
        switch access.source {
        case .lifetime:
            return String(localized: "永久版", defaultValue: "永久版")
        case .subscription:
            return String(localized: "订阅中", defaultValue: "订阅中")
        case .dayPass:
            return String(localized: "24 小时通行证", defaultValue: "24 小时通行证")
        case .trial:
            return String(localized: "24 小时体验", defaultValue: "24 小时体验")
        case .none:
            return String(localized: "免费额度", defaultValue: "免费额度")
        }
    }
}
