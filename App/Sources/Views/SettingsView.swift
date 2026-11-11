import SwiftUI
import LingXiKit

/// Native inset-grouped settings: language, Pro, about. Presented as a large sheet with a
/// Done action, matching the system Settings language instead of a custom card stack.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: PurchaseManager
    var onClose: () -> Void
    var controlInset: CGFloat = 0

    @State private var language = AppLanguage.current
    @State private var showLanguageChanged = false
    @State private var showPro = false
    @State private var showTutorial = false
    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                AmbientBackdrop(intensity: .quiet)

                Form {
                    Section {
                        Button {
                            showPro = true
                        } label: {
                            proRow
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .accessibilityIdentifier("settings.proRow")
                    }

                    Section {
                        LivePhotoModeSelector(
                            selection: model.livePhotoModePreference,
                            onSelect: { model.setLivePhotoModePreference($0) }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("settings.livePhotoMode")
                    } header: {
                        Text(String(localized: "settings.livePhoto.section", defaultValue: "实况照片处理方式"))
                    } footer: {
                        Text(String(localized: "settings.livePhoto.footer", defaultValue: "这里保存的是默认值。选择照片时仍然可以临时切换，临时选择不会改动这里。"))
                    }

                    Section {
                        Button {
                            showTutorial = true
                        } label: {
                            HStack(spacing: Spacing.s) {
                                Image(systemName: "book")
                                    .font(.system(.body, design: .default, weight: .medium))
                                    .foregroundStyle(Palette.textSecondary)
                                    .frame(width: 22)
                                Text(String(localized: "教程", defaultValue: "使用教程"))
                                    .font(Typography.body)
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.tutorial")
                    } header: {
                        Text(String(localized: "帮助", defaultValue: "帮助"))
                    }

                    Section {
                        ForEach(AppLanguage.allCases) { option in
                            Button {
                                select(option)
                            } label: {
                                HStack(spacing: Spacing.s) {
                                    Text(option.nativeName)
                                        .font(Typography.body)
                                        .foregroundStyle(Palette.textPrimary)
                                    Spacer(minLength: 0)
                                    if language == option {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Palette.accentText)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(language == option ? .isSelected : [])
                        }
                    } header: {
                        Text(String(localized: "settings.language.section", defaultValue: "语言"))
                    } footer: {
                        Text(String(localized: "settings.language.note", defaultValue: "语言只影响界面显示。切换后需要从多任务界面关闭并重新打开 App。"))
                    }

                    Section {
                        LabeledContent(String(localized: "settings.about.version", defaultValue: "版本"),
                                       value: versionText)
                        NavigationLink(String(localized: "settings.about.privacy", defaultValue: "隐私说明")) {
                            PrivacyDetailView()
                        }
                        NavigationLink(String(localized: "settings.about.licenses", defaultValue: "第三方许可")) {
                            LicensesDetailView()
                        }
                    } header: {
                        Text(String(localized: "settings.about.section", defaultValue: "关于"))
                    } footer: {
                        Text(String(localized: "settings.footer", defaultValue: "照片始终只在本机处理。"))
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .duoSheetWidth()
            .navigationTitle(String(localized: "settings.title", defaultValue: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { onClose() }
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Palette.accentText)
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .task {
            if purchases.product == nil { await purchases.loadProduct() }
        }
        .sheet(isPresented: $showPro) {
            ProPurchaseView(
                purchases: purchases,
                onEntitlementChanged: {
                    Task { await model.refreshQuota() }
                },
                onClose: { showPro = false },
                controlInset: controlInset
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView(model: model, isFirstRun: false) { showTutorial = false }
        }
        .alert(String(localized: "settings.language.changedTitle", defaultValue: "语言已切换"),
               isPresented: $showLanguageChanged) {
            Button(String(localized: "完成")) {}
        } message: {
            Text(String(localized: "settings.language.changedMessage", defaultValue: "请从多任务界面关闭 App，再重新打开。"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings.title", defaultValue: "设置"))
    }

    private var proRow: some View {
        HStack(spacing: Spacing.s) {
            BrandMark(size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Brand.proName)
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Text(proSubtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "settings.pro.action", defaultValue: "查看 Pro"))
    }

    private var proSubtitle: String {
        if purchases.isPro {
            return String(localized: "pro.owner.card", defaultValue: "已解锁 \(Brand.proName)")
        }
        return String(localized: "settings.pro.subtitle", defaultValue: "一次购买，永久不限张数。")
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func select(_ option: AppLanguage) {
        guard option != language else { return }
        AppLanguage.apply(option)
        language = option
        showLanguageChanged = true
    }
}

private struct PrivacyDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("照片只在本机处理")
                    .font(Typography.section)
                    .foregroundStyle(Palette.textPrimary)
                Text("纹粒读取你选择的 HEIC 原片，只追加纹理与颗粒层，然后把结果保存为一张新照片。原图不会被覆盖或转码。处理过程不上传照片，也不依赖云端服务。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                Text("免费额度与 Pro 权益记录在本机钥匙串中；购买交易由 App Store 验证，App 不接触你的支付信息。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.l)
        }
        .background(Palette.background)
        .navigationTitle(String(localized: "settings.about.privacy", defaultValue: "隐私说明"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicensesDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("纹理与颗粒渲染")
                    .font(Typography.status)
                    .foregroundStyle(Palette.textPrimary)
                Text("本 App 的 HEIC 纹理补全能力基于 Shalielie 的开源实现，按其许可证使用。完整许可证见仓库 ThirdPartyNotices/Shalielie-LICENSE.txt。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                Text("其余界面、状态机与校验逻辑由 LingXiStyle 项目实现。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.l)
        }
        .background(Palette.background)
        .navigationTitle(String(localized: "settings.about.licenses", defaultValue: "第三方许可"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("设置 · 浅色") {
    let model = PreviewFixtures.model(screen: .idle, items: [])
    SettingsView(model: model, purchases: model.purchases, onClose: {})
        .preferredColorScheme(.light)
}

#Preview("设置 · 深色") {
    let model = PreviewFixtures.model(screen: .idle, items: [])
    SettingsView(model: model, purchases: model.purchases, onClose: {})
        .preferredColorScheme(.dark)
}
#endif
