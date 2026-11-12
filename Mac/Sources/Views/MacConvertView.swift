import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LingXiKit

struct MacConvertView: View {
    @ObservedObject var model: MacModel
    @State private var isExportFolderPresented = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MacSpacing.l) {
                    header
                    dropZone
                    exportRow
                    if !model.items.isEmpty { queue }
                    if model.screen == .result { summary }
                }
                .padding(MacSpacing.xl)
                .frame(maxWidth: 980, alignment: .leading)
            }
            Divider()
            actionBar
        }
        .background(MacPalette.background)
        .fileImporter(isPresented: $model.isImportPresented,
                      allowedContentTypes: [.heic, .heif],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFiles(urls) }
        }
        .fileImporter(isPresented: $model.isFolderImportPresented,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result { model.importFiles(urls) }
        }
        .fileImporter(isPresented: $isExportFolderPresented,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.setExportFolder(url)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MacSpacing.xs) {
            Text(String(localized: "转换", defaultValue: "转换"))
                .font(MacType.display)
            Text(String(localized: "mac.convert.subtitle",
                        defaultValue: "拖入 iPhone 拍摄的 HEIC 原片。纹粒只会追加一层纹理与颗粒，不转码、不覆盖原片、不上传。"))
                .font(MacType.body)
                .foregroundStyle(MacPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dropZone: some View {
        VStack(spacing: MacSpacing.s) {
            Image(systemName: model.isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(model.isDropTargeted ? MacPalette.accent : MacPalette.textTertiary)
            Text(String(localized: "把 HEIC 拖到这里", defaultValue: "把 HEIC 拖到这里"))
                .font(MacType.section)
            Text(String(localized: "mac.convert.dropHint",
                        defaultValue: "支持多选和整个文件夹。实况照片请把同目录同名的 .MOV 一起拖入。"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: MacSpacing.s) {
                Button(String(localized: "选择照片…", defaultValue: "选择照片…")) {
                    model.isImportPresented = true
                }
                .buttonStyle(MacQuietButtonStyle())
                Button(String(localized: "选择文件夹…", defaultValue: "选择文件夹…")) {
                    model.isFolderImportPresented = true
                }
                .buttonStyle(MacQuietButtonStyle())
            }
            .padding(.top, MacSpacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MacSpacing.xl)
        .background(RoundedRectangle(cornerRadius: MacRadius.card, style: .continuous)
            .fill(model.isDropTargeted ? MacPalette.accentSoft : MacPalette.surface))
        .overlay(RoundedRectangle(cornerRadius: MacRadius.card, style: .continuous)
            .strokeBorder(model.isDropTargeted ? MacPalette.accent : MacPalette.hairline.opacity(0.8),
                          style: StrokeStyle(lineWidth: model.isDropTargeted ? 1.5 : 1, dash: [6, 5])))
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls)
            return true
        } isTargeted: { targeted in
            model.isDropTargeted = targeted
        }
    }

    private var exportRow: some View {
        HStack(spacing: MacSpacing.xs) {
            Image(systemName: "folder")
                .foregroundStyle(MacPalette.textSecondary)
            Text(String(localized: "导出到", defaultValue: "导出到"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
            Text(model.exportFolder?.path ?? String(localized: "尚未选择", defaultValue: "尚未选择"))
                .font(MacType.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: MacSpacing.s)
            Button(String(localized: "更改…", defaultValue: "更改…")) {
                isExportFolderPresented = true
            }
            .buttonStyle(.link)
            .font(MacType.caption)
        }
    }

    private var queue: some View {
        MacCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 68) }
                    row(item)
                }
            }
        }
    }

    private func row(_ item: MacModel.Item) -> some View {
        HStack(spacing: MacSpacing.s) {
            MacThumbnailView(url: item.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(MacType.bodyEmphasized)
                    .lineLimit(1)
                HStack(spacing: MacSpacing.xs) {
                    if item.isLivePhoto {
                        Text("LIVE")
                            .font(MacType.micro)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(MacPalette.accentSoft))
                            .foregroundStyle(MacPalette.accentText)
                    }
                    Text(metaText(item))
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.textSecondary)
                }
            }
            Spacer(minLength: MacSpacing.s)
            status(item)
            if !model.isConverting {
                Button {
                    model.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(MacPalette.textTertiary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "移出列表", defaultValue: "移出列表"))
            }
        }
        .padding(.horizontal, MacSpacing.m)
        .padding(.vertical, MacSpacing.xs)
    }

    private func metaText(_ item: MacModel.Item) -> String {
        var parts: [String] = []
        if let byteCount = item.byteCount { parts.append(MacModel.byteText(byteCount)) }
        if case .unsupported(let message) = item.state { parts.append(message) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func status(_ item: MacModel.Item) -> some View {
        switch item.state {
        case .inspecting:
            HStack(spacing: MacSpacing.xxs) {
                ProgressView().controlSize(.small)
                Text(String(localized: "检查中", defaultValue: "检查中"))
            }
            .font(MacType.caption)
            .foregroundStyle(MacPalette.textSecondary)
        case .ready:
            Text(String(localized: "待转换", defaultValue: "待转换"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
        case .unsupported(let message):
            Label {
                Text(message).lineLimit(1)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(MacType.caption)
            .foregroundStyle(MacPalette.warning)
            .frame(maxWidth: 260, alignment: .trailing)
        case .converting(let stage):
            HStack(spacing: MacSpacing.xxs) {
                ProgressView().controlSize(.small)
                Text(stageText(stage))
            }
            .font(MacType.caption)
            .foregroundStyle(MacPalette.textSecondary)
        case .saved:
            Label(String(localized: "已保存", defaultValue: "已保存"),
                  systemImage: "checkmark.circle.fill")
                .font(MacType.caption)
                .foregroundStyle(MacPalette.success)
        case .failed(let message):
            Label {
                Text(message).lineLimit(2)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            .font(MacType.caption)
            .foregroundStyle(MacPalette.error)
            .frame(maxWidth: 260, alignment: .trailing)
        case .cancelled:
            Text(String(localized: "已取消", defaultValue: "已取消"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
        case .deferred:
            Text(String(localized: "额度不足，待下次", defaultValue: "额度不足，待下次"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.warning)
        }
    }

    private func stageText(_ stage: ConversionStage) -> String {
        if stage == .saving {
            return String(localized: "mac.stage.saving", defaultValue: "正在写入文件")
        }
        return stage.inProgressTitle
    }

    private var summary: some View {
        let saved = model.items.filter(\.isSaved).count
        let failed = model.items.filter { if case .failed = $0.state { return true }; return false }.count
        let cancelled = model.items.filter { $0.state == .cancelled }.count
        let deferred = model.items.filter { $0.state == .deferred }.count
        return MacCard {
            VStack(alignment: .leading, spacing: MacSpacing.s) {
                Text(saved > 0
                     ? String(localized: "本次完成", defaultValue: "本次完成")
                     : String(localized: "本次没有保存成果", defaultValue: "本次没有保存成果"))
                    .font(MacType.section)
                HStack(spacing: MacSpacing.l) {
                    stat(String(localized: "成功", defaultValue: "成功"), value: saved, tint: MacPalette.success)
                    stat(String(localized: "失败", defaultValue: "失败"), value: failed, tint: MacPalette.error)
                    stat(String(localized: "取消", defaultValue: "取消"), value: cancelled, tint: MacPalette.textSecondary)
                    stat(String(localized: "待额度", defaultValue: "待额度"), value: deferred, tint: MacPalette.warning)
                }
                HStack(spacing: MacSpacing.s) {
                    if let folder = model.exportFolder, saved > 0 {
                        Button(String(localized: "在 Finder 中显示", defaultValue: "在 Finder 中显示")) {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                        .buttonStyle(MacQuietButtonStyle())
                    }
                    if failed + deferred + cancelled > 0 {
                        Button(String(localized: "重试未完成的", defaultValue: "重试未完成的")) {
                            model.retryFailed()
                        }
                        .buttonStyle(MacQuietButtonStyle())
                    }
                    Spacer()
                    Button(String(localized: "清空列表", defaultValue: "清空列表")) {
                        model.removeAll()
                    }
                    .buttonStyle(.link)
                    .font(MacType.caption)
                }
            }
        }
    }

    private func stat(_ title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(MacType.statNumber)
                .foregroundStyle(tint)
            Text(title)
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: MacSpacing.s) {
            Text(queueLine)
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
            if !model.quota.isPro {
                Text(String(localized: "升级 Pro 后不限张数", defaultValue: "升级 Pro 后不限张数"))
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.textTertiary)
            }
            Spacer()
            if model.isConverting {
                ProgressView().controlSize(.small)
                Button(String(localized: "取消", defaultValue: "取消")) {
                    model.cancelConversion()
                }
                .buttonStyle(MacQuietButtonStyle())
                .disabled(model.isCancelling)
            } else {
                if !model.quota.isPro && model.quota.remaining == 0 {
                    Button(String(localized: "查看 Pro", defaultValue: "查看 Pro")) {
                        model.isPurchasePresented = true
                    }
                    .buttonStyle(MacQuietButtonStyle())
                }
                Button(String(localized: "开始转换", defaultValue: "开始转换")) {
                    model.startConversion()
                }
                .buttonStyle(MacPrimaryButtonStyle())
                .disabled(readyCount == 0)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(.horizontal, MacSpacing.l)
        .padding(.vertical, MacSpacing.s)
        .background(MacPalette.surfaceElevated)
    }

    private var readyCount: Int {
        model.items.filter { $0.state == .ready || $0.isRetryable }.count
    }

    private var queueLine: String {
        if model.quota.isPro {
            return String(localized: "mac.queue.pro",
                          defaultValue: "\(readyCount) 张待转换 · Pro 不限张数")
        }
        return String(localized: "mac.queue.free",
                      defaultValue: "\(readyCount) 张待转换 · 今日剩余 \(model.quota.remaining) 张")
    }
}
