import AppKit
import SwiftUI
import LingXiKit

struct MacVaultView: View {
    @ObservedObject var model: MacModel
    @State private var selection: UUID?

    private var selected: VaultRecord? {
        guard let selection else { return nil }
        return model.vaultRecords.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.vaultRecords.isEmpty {
                empty
            } else {
                HSplitView {
                    list
                        .frame(minWidth: 320, idealWidth: 380)
                    detail
                        .frame(minWidth: 320)
                }
            }
        }
        .background(MacPalette.background)
        .onChange(of: model.vaultRecords) { _, records in
            if let selection, !records.contains(where: { $0.id == selection }) {
                self.selection = records.first?.id
            } else if selection == nil {
                selection = records.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MacSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "成果保险箱", defaultValue: "成果保险箱"))
                        .font(MacType.display)
                    Text(String(localized: "mac.vault.subtitle",
                                defaultValue: "转换完成的结果会在这里保留一段时间。重新保存或导出都不会再扣额度。"))
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.textSecondary)
                }
                Spacer()
                Menu {
                    ForEach(VaultRetention.allCases) { retention in
                        Button {
                            model.setRetention(retention)
                        } label: {
                            Text(retention.title)
                        }
                    }
                } label: {
                    Label(String(localized: "保留 %@", defaultValue: "保留 \(model.vaultRetention.title)"),
                          systemImage: "clock")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button(String(localized: "清理过期", defaultValue: "清理过期")) {
                    model.purgeExpired()
                }
                .buttonStyle(MacQuietButtonStyle())
            }
            HStack(spacing: MacSpacing.l) {
                metric(String(localized: "成果", defaultValue: "成果"),
                       value: "\(model.vaultRecords.count)")
                metric(String(localized: "占用", defaultValue: "占用"),
                       value: MacModel.byteText(model.vaultByteCount))
                if let available = model.vaultAvailable {
                    metric(String(localized: "设备可用", defaultValue: "设备可用"),
                           value: MacModel.byteText(Int(clamping: available)))
                }
                Spacer()
                Button(String(localized: "清空保险箱", defaultValue: "清空保险箱")) {
                    model.clearVault()
                }
                .buttonStyle(.link)
                .font(MacType.caption)
                .disabled(model.vaultRecords.isEmpty)
            }
        }
        .padding(MacSpacing.xl)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(MacType.numeric)
            Text(title)
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.vaultRecords) { record in
                VaultRow(record: record, model: model)
                    .tag(record.id)
                    .contextMenu {
                        Button(String(localized: "导出…", defaultValue: "导出…")) { model.export(record) }
                        Button(String(localized: "在 Finder 中显示", defaultValue: "在 Finder 中显示")) { model.reveal(record) }
                        Divider()
                        Button(String(localized: "删除", defaultValue: "删除"), role: .destructive) {
                            model.delete(record)
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var detail: some View {
        if let record = selected {
            VaultDetail(record: record, model: model)
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: MacSpacing.s) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(MacPalette.textTertiary)
            Text(String(localized: "保险箱还是空的", defaultValue: "保险箱还是空的"))
                .font(MacType.section)
            Text(String(localized: "mac.vault.empty",
                        defaultValue: "转换完成的照片会留在这里，最多按你所选的期限保存。"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VaultRow: View {
    let record: VaultRecord
    @ObservedObject var model: MacModel

    var body: some View {
        HStack(spacing: MacSpacing.s) {
            MacThumbnailView(url: model.vaultStore.photoURL(for: record), side: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(MacType.bodyEmphasized)
                    .lineLimit(1)
                HStack(spacing: MacSpacing.xs) {
                    if record.isLivePhoto {
                        Text("LIVE")
                            .font(MacType.micro)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(MacPalette.accentSoft))
                            .foregroundStyle(MacPalette.accentText)
                    }
                    Text(record.remainingText())
                        .font(MacType.caption)
                        .foregroundStyle(record.isExpired() ? MacPalette.error : MacPalette.textSecondary)
                    Text(MacModel.byteText(record.totalByteCount))
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

private struct VaultDetail: View {
    let record: VaultRecord
    @ObservedObject var model: MacModel
    @State private var preview: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                MacPalette.background
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(MacSpacing.m)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: MacSpacing.s) {
                Text(record.displayName)
                    .font(MacType.section)
                    .lineLimit(2)
                Grid(alignment: .leading, horizontalSpacing: MacSpacing.m, verticalSpacing: 4) {
                    infoRow(String(localized: "创建", defaultValue: "创建"),
                            record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    infoRow(String(localized: "保留", defaultValue: "保留"), record.remainingText())
                    infoRow(String(localized: "大小", defaultValue: "大小"), MacModel.byteText(record.totalByteCount))
                    infoRow(String(localized: "类型", defaultValue: "类型"),
                            record.isLivePhoto
                                ? String(localized: "实况照片", defaultValue: "实况照片")
                                : String(localized: "静态照片", defaultValue: "静态照片"))
                }
                HStack(spacing: MacSpacing.s) {
                    Button(String(localized: "导出…", defaultValue: "导出…")) {
                        model.export(record)
                    }
                    .buttonStyle(MacPrimaryButtonStyle())
                    Button(String(localized: "在 Finder 中显示", defaultValue: "在 Finder 中显示")) {
                        model.reveal(record)
                    }
                    .buttonStyle(MacQuietButtonStyle())
                    Spacer()
                    Button(String(localized: "删除", defaultValue: "删除"), role: .destructive) {
                        model.delete(record)
                    }
                    .buttonStyle(MacQuietButtonStyle())
                }
                .padding(.top, MacSpacing.xxs)
            }
            .padding(MacSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: record.id) {
            let url = model.vaultStore.photoURL(for: record)
            let loaded = await Task.detached(priority: .userInitiated) {
                VaultPreviewBox(image: MacThumbnail.image(at: url, maxPixel: 1600))
            }.value
            preview = loaded.image
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
            Text(value)
                .font(MacType.caption)
        }
    }
}

private final class VaultPreviewBox: @unchecked Sendable {
    let image: NSImage?
    init(image: NSImage?) { self.image = image }
}
