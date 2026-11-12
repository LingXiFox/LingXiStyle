import SwiftUI
import UIKit
import LingXiKit

/// In-app result vault: keeps converted photos (still or Live Photo) for a retention
/// window so a saved result can be re-saved or exported without spending free quota.
struct VaultView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void
    var controlInset: CGFloat = 0

    var body: some View {
        NavigationStack {
            VaultContent(model: model, controlInset: controlInset)
                .navigationTitle(String(localized: "vault.title", defaultValue: "成果保险箱"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成")) { onClose() }
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(Palette.accentText)
                            .accessibilityIdentifier("vault.done")
                    }
                }
        }
    }
}

/// Vault body without navigation chrome so it can also be pushed from Settings.
struct VaultContent: View {
    @ObservedObject var model: AppModel
    var controlInset: CGFloat = 0

    @State private var previewRecord: VaultRecord?
    @State private var pendingDelete: VaultRecord?
    @State private var showClearAll = false
    @State private var resavingID: UUID?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            AmbientBackdrop(intensity: .quiet)

            ScrollView {
                VStack(spacing: Spacing.m) {
                    summaryCard
                    retentionCard
                    recordsSection
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xl + controlInset)
                .frame(maxWidth: Layout.iPadContentMaxWidth)
            }
        }
        .sheet(item: $previewRecord) { record in
            VaultPreviewView(record: record, photoURL: model.vaultStore.photoURL(for: record))
        }
        .alert(String(localized: "vault.message.title", defaultValue: "保险箱"),
               isPresented: Binding(get: { model.vaultMessage != nil },
                                    set: { if !$0 { model.vaultMessage = nil } })) {
            Button(String(localized: "好")) { model.vaultMessage = nil }
        } message: {
            Text(model.vaultMessage ?? "")
        }
        .alert(String(localized: "vault.delete.title", defaultValue: "删除这份成果？"),
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button(String(localized: "取消"), role: .cancel) { pendingDelete = nil }
            Button(String(localized: "删除"), role: .destructive) {
                if let record = pendingDelete { model.deleteVaultRecord(record) }
                pendingDelete = nil
            }
        } message: {
            Text(String(localized: "vault.delete.message", defaultValue: "保险箱里的文件会被移除，已保存到相册的照片不受影响。"))
        }
        .confirmationDialog(String(localized: "vault.clearAll.title", defaultValue: "清空保险箱？"),
                            isPresented: $showClearAll,
                            titleVisibility: .visible) {
            Button(String(localized: "清空"), role: .destructive) { model.deleteAllVaultRecords() }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "vault.clearAll.message", defaultValue: "所有保留中的成果都会被删除，已保存到相册的照片不受影响。"))
        }
        .onAppear { model.refreshVault() }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(String(localized: "vault.summary.count", defaultValue: "保留中"))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                Text("\(model.vaultRecords.count)")
                    .font(Typography.statNumber)
                    .foregroundStyle(Palette.textPrimary)
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(String(localized: "vault.summary.size", defaultValue: "占用空间"))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                Text(AppModel.byteText(model.vaultTotalByteCount))
                    .font(Typography.numeric)
                    .foregroundStyle(Palette.textPrimary)
            }

            if let available = model.vaultAvailableByteCount {
                Text(String(localized: "vault.summary.available",
                            defaultValue: "设备可用空间 \(AppModel.byteText(available))"))
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textTertiary)
            }

            if model.vaultRecords.contains(where: { $0.isExpired() }) {
                Button {
                    model.purgeExpiredVault()
                } label: {
                    Label(String(localized: "vault.cleanup", defaultValue: "清理已过期成果"),
                          systemImage: "trash.slash")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.accentText)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vault.cleanup")
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Retention

    private var retentionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Text(String(localized: "vault.retention.title", defaultValue: "保留期限"))
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Menu {
                    ForEach(VaultRetention.allCases) { option in
                        Button {
                            model.setVaultRetention(option)
                        } label: {
                            if option == model.vaultRetention {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.vaultRetention.title)
                            .font(Typography.captionEmphasized)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accentText)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 6)
                    .background(Palette.accentSoft, in: Capsule())
                }
                .accessibilityIdentifier("vault.retentionMenu")
            }

            Text(String(localized: "vault.retention.footer",
                        defaultValue: "新成果按此期限保留。调整后从今天重新计时，已过期的成果可在上方手动清理。"))
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.vaultRecords.isEmpty {
                Button(String(localized: "vault.clearAll.button", defaultValue: "清空保险箱")) {
                    showClearAll = true
                }
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.error)
                .buttonStyle(.plain)
                .accessibilityIdentifier("vault.clearAll")
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Records

    @ViewBuilder
    private var recordsSection: some View {
        if model.vaultRecords.isEmpty {
            VStack(spacing: Spacing.s) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                Text(String(localized: "vault.empty.title", defaultValue: "保险箱还是空的"))
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Text(String(localized: "vault.empty.message",
                            defaultValue: "转换完成的照片会在这里保留一段时间，方便重新保存或导出。"))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: Spacing.xs) {
                ForEach(model.vaultRecords) { record in
                    VaultRow(
                        record: record,
                        thumbnailURL: model.vaultStore.photoURL(for: record),
                        isResaving: resavingID == record.id,
                        onPreview: { previewRecord = record },
                        onResave: { resave(record) },
                        onDelete: { pendingDelete = record }
                    )
                }
            }
        }
    }

    private func resave(_ record: VaultRecord) {
        guard resavingID == nil else { return }
        resavingID = record.id
        Task {
            await model.resaveFromVault(record)
            resavingID = nil
        }
    }
}

// MARK: - Row

private struct VaultRow: View {
    let record: VaultRecord
    let thumbnailURL: URL?
    let isResaving: Bool
    var onPreview: () -> Void
    var onResave: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Button(action: onPreview) {
                AsyncFileImage(url: thumbnailURL)
                    .frame(width: 56, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "vault.preview", defaultValue: "预览"))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.displayName)
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if record.isLivePhoto {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Palette.accentText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                Text(metaText)
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)

                HStack(spacing: Spacing.s) {
                    Button(action: onResave) {
                        if isResaving {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text(String(localized: "vault.resave", defaultValue: "重新保存"))
                        }
                    }
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(Palette.accentText)
                    .buttonStyle(.plain)
                    .disabled(isResaving)
                    .accessibilityIdentifier("vault.resave")

                    ShareLink(items: shareURLs) {
                        Text(String(localized: "vault.share", defaultValue: "导出"))
                            .font(Typography.captionEmphasized)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityIdentifier("vault.share")

                    Menu {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label(String(localized: "删除"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityIdentifier("vault.more")
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .opacity(record.isExpired() ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    private var shareURLs: [URL] {
        if let photo = thumbnailURL { return [photo] }
        return []
    }

    private var metaText: String {
        let now = Date()
        let remaining = record.remainingLifetime(at: now)
        let timeText: String
        if record.retention == .forever {
            timeText = String(localized: "vault.meta.forever", defaultValue: "长期保留")
        } else if let remaining, remaining > 0 {
            timeText = String(localized: "vault.meta.remaining",
                              defaultValue: "剩余 \(AppModel.lifetimeText(remaining))")
        } else {
            timeText = String(localized: "vault.meta.expired", defaultValue: "已过期")
        }
        return "\(timeText) · \(AppModel.byteText(record.totalByteCount))"
    }

}

// MARK: - Preview

private struct VaultPreviewView: View {
    let record: VaultRecord
    let photoURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncFileImage(url: photoURL, contentMode: .fit)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle(record.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                        .foregroundStyle(Palette.accentText)
                }
            }
        }
    }
}

// MARK: - Async file image

/// Loads a full-size file image off the main thread and only assigns it once loaded.
struct AsyncFileImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.fillControl
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: url) {
            guard let url else { return }
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: url.path)
            }.value
            image = loaded
        }
    }
}
