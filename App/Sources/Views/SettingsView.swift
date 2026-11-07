import SwiftUI
import LingXiKit

/// App-level preferences: interface language and the lifetime Pro purchase. It deliberately
/// does not call the product a subscription; the product is a one-time non-consumable.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: PurchaseManager
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var language = AppLanguage.current
    @State private var showLanguageChanged = false
    @State private var showPro = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ambientLight

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar

                    Text(String(localized: "settings.title", defaultValue: "设置"))
                        .font(.system(.largeTitle, design: .default, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.top, Spacing.l)
                        .accessibilityAddTraits(.isHeader)

                    languageSection
                        .padding(.top, Spacing.xl)

                    proSection
                        .padding(.top, Spacing.l)

                    Text(String(localized: "settings.footer", defaultValue: "语言只影响界面显示；照片始终只在本机处理。"))
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.l)
                        .padding(.bottom, Spacing.l)
                }
                .padding(.horizontal, Spacing.margin(for: 390))
            }
            .scrollBounceBehavior(.basedOnSize)
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
                onClose: { showPro = false }
            )
            .presentationDragIndicator(.visible)
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

    private var topBar: some View {
        HStack {
            Text(Brand.name.uppercased())
                .font(.system(.caption2, design: .default, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(Palette.accentText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                    .background(Palette.surface.opacity(0.8), in: Circle())
            }
            .accessibilityLabel(String(localized: "settings.close", defaultValue: "关闭设置"))
        }
        .padding(.top, Spacing.s)
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionLabel(String(localized: "settings.language.section", defaultValue: "语言"))

            VStack(spacing: 0) {
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
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .frame(minHeight: Layout.minimumTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(language == option ? .isSelected : [])

                    if option != AppLanguage.allCases.last {
                        Divider()
                            .overlay(Palette.hairline)
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))

            Text(String(localized: "settings.language.note", defaultValue: "切换语言后，需要重新打开 App 才会生效。"))
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var proSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionLabel("PRO")

            Button {
                showPro = true
            } label: {
                HStack(spacing: Spacing.s) {
                    ZStack {
                        Circle()
                            .fill(Palette.accent.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: purchases.isPro ? "checkmark.seal.fill" : "sparkles")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(purchases.isPro ? Palette.success : Palette.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(Brand.proName)
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(Palette.textPrimary)
                        Text(proSubtitle)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary.opacity(0.7))
                }
                .padding(Spacing.m)
                .frame(minHeight: Layout.minimumTouchTarget)
                .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "settings.pro.action", defaultValue: "查看 Pro"))
        }
    }

    private var proSubtitle: String {
        if purchases.isPro {
            return String(localized: "pro.owner.card", defaultValue: "已解锁 \(Brand.proName)")
        }
        if let product = purchases.product {
            return String(localized: "pro.purchase.price", defaultValue: "永久解锁 · \(product.displayPrice)")
        }
        return String(localized: "settings.pro.subtitle", defaultValue: "一次购买，永久解锁无限照片转换。")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.captionEmphasized)
            .foregroundStyle(Palette.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, Spacing.xxs)
    }

    private func select(_ option: AppLanguage) {
        guard option != language else { return }
        AppLanguage.apply(option)
        language = option
        showLanguageChanged = true
    }

    private var ambientLight: some View {
        ZStack {
            RadialGradient(colors: [Palette.accent.opacity(colorScheme == .dark ? 0.17 : 0.10), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 360)
                .offset(x: -100, y: -130)
            RadialGradient(colors: [Palette.accentSecondary.opacity(colorScheme == .dark ? 0.12 : 0.07), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 320)
                .offset(x: 120, y: 140)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
