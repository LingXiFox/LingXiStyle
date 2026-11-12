import SwiftUI
import LingXiKit

enum MacSection: String, CaseIterable, Identifiable {
    case convert
    case vault
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: return String(localized: "转换", defaultValue: "转换")
        case .vault: return String(localized: "成果保险箱", defaultValue: "成果保险箱")
        case .history: return String(localized: "任务历史", defaultValue: "任务历史")
        }
    }

    var icon: String {
        switch self {
        case .convert: return "wand.and.stars"
        case .vault: return "shippingbox"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct MacRootView: View {
    @ObservedObject var model: MacModel
    @State private var selection: MacSection = .convert
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(MacSection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
        } detail: {
            switch selection {
            case .convert:
                MacConvertView(model: model)
            case .vault:
                MacVaultView(model: model)
            case .history:
                MacHistoryView(model: model)
            }
        }
        .navigationTitle(selection.title)
        .overlay(alignment: .bottom) { noticeBar }
        .sheet(isPresented: $model.isPurchasePresented) {
            MacPurchaseView(model: model)
                .frame(minWidth: 560, minHeight: 640)
        }
        .onChange(of: model.notice) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if model.notice == newValue { model.notice = nil }
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: MacSpacing.xs) {
            Divider()
            HStack(spacing: MacSpacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(MacPalette.accent)
                Text(Brand.name)
                    .font(MacType.brand)
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(MacPalette.textSecondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "设置", defaultValue: "设置"))
            }
            Text(quotaLine)
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
            if !model.quota.isPro {
                Button(String(localized: "升级 %@", defaultValue: "升级 \(Brand.proName)")) {
                    model.isPurchasePresented = true
                }
                .buttonStyle(.link)
                .font(MacType.caption)
            }
        }
        .padding(.horizontal, MacSpacing.s)
        .padding(.vertical, MacSpacing.s)
    }

    private var quotaLine: String {
        if model.quota.isPro {
            return String(localized: "mac.quota.pro", defaultValue: "\(Brand.proName) · 不限张数")
        }
        guard model.quota.isAvailable else {
            return String(localized: "mac.quota.unavailable", defaultValue: "今日额度暂不可用")
        }
        return String(localized: "mac.quota.free",
                      defaultValue: "今日剩余 \(model.quota.remaining) / \(model.quota.limit) 张")
    }

    @ViewBuilder
    private var noticeBar: some View {
        if let notice = model.notice {
            HStack(spacing: MacSpacing.xs) {
                Image(systemName: "info.circle")
                    .foregroundStyle(MacPalette.accent)
                Text(notice)
                    .font(MacType.caption)
                Spacer(minLength: MacSpacing.s)
                Button {
                    model.notice = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacPalette.textSecondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, MacSpacing.m)
            .padding(.vertical, MacSpacing.s)
            .background(RoundedRectangle(cornerRadius: MacRadius.group, style: .continuous)
                .fill(MacPalette.surfaceElevated)
                .shadow(color: MacPalette.shadowColor, radius: 12, y: 4))
            .overlay(RoundedRectangle(cornerRadius: MacRadius.group, style: .continuous)
                .strokeBorder(MacPalette.hairline.opacity(0.6), lineWidth: 0.5))
            .padding(MacSpacing.l)
            .frame(maxWidth: 560)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
