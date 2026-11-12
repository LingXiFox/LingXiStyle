import AppKit
import SwiftUI
import LingXiKit

struct MacHistoryView: View {
    @ObservedObject var model: MacModel
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.history.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: MacSpacing.s) {
                        ForEach(model.history) { task in
                            taskCard(task)
                        }
                    }
                    .padding(MacSpacing.xl)
                    .frame(maxWidth: 900, alignment: .leading)
                }
            }
        }
        .background(MacPalette.background)
        .onAppear { model.refreshHistory() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "任务历史", defaultValue: "任务历史"))
                .font(MacType.display)
            Text(String(localized: "mac.history.subtitle",
                        defaultValue: "每次转换都留一条记录：张数、状态和失败原因。退出后中断的任务会在下次启动时补记。"))
                .font(MacType.caption)
                .foregroundStyle(MacPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MacSpacing.xl)
    }

    private var empty: some View {
        VStack(spacing: MacSpacing.s) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(MacPalette.textTertiary)
            Text(String(localized: "还没有任务记录", defaultValue: "还没有任务记录"))
                .font(MacType.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func taskCard(_ task: ConversionTaskRecord) -> some View {
        let isExpanded = expanded.contains(task.id)
        return MacCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    if isExpanded { expanded.remove(task.id) } else { expanded.insert(task.id) }
                } label: {
                    HStack(spacing: MacSpacing.s) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacPalette.textTertiary)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(MacType.bodyEmphasized)
                            Text(counts(task))
                                .font(MacType.caption)
                                .foregroundStyle(MacPalette.textSecondary)
                        }
                        Spacer()
                        statePill(task)
                    }
                    .padding(.horizontal, MacSpacing.m)
                    .padding(.vertical, MacSpacing.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(task.items) { item in
                            itemRow(item)
                            if item.id != task.items.last?.id {
                                Divider().padding(.leading, MacSpacing.m)
                            }
                        }
                    }
                }
            }
        }
    }

    private func counts(_ task: ConversionTaskRecord) -> String {
        var parts: [String] = []
        parts.append(String(localized: "共 %lld 张", defaultValue: "共 \(task.items.count) 张"))
        if task.savedCount > 0 {
            parts.append(String(localized: "成功 %lld", defaultValue: "成功 \(task.savedCount)"))
        }
        if task.failedCount > 0 {
            parts.append(String(localized: "失败 %lld", defaultValue: "失败 \(task.failedCount)"))
        }
        if task.cancelledCount > 0 {
            parts.append(String(localized: "取消 %lld", defaultValue: "取消 \(task.cancelledCount)"))
        }
        return parts.joined(separator: " · ")
    }

    private func statePill(_ task: ConversionTaskRecord) -> some View {
        Text(stateText(task.state))
            .font(MacType.micro)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint(task.state).opacity(0.16)))
            .foregroundStyle(tint(task.state))
    }

    private func stateText(_ state: ConversionTaskState) -> String {
        switch state {
        case .running: return String(localized: "进行中", defaultValue: "进行中")
        case .waitingToSave: return String(localized: "待保存", defaultValue: "待保存")
        case .completed: return String(localized: "已完成", defaultValue: "已完成")
        case .partiallyCompleted: return String(localized: "部分完成", defaultValue: "部分完成")
        case .failed: return String(localized: "失败", defaultValue: "失败")
        case .cancelled: return String(localized: "已取消", defaultValue: "已取消")
        case .interrupted: return String(localized: "中断", defaultValue: "中断")
        }
    }

    private func tint(_ state: ConversionTaskState) -> Color {
        switch state {
        case .completed: return MacPalette.success
        case .partiallyCompleted, .waitingToSave, .running: return MacPalette.accentText
        case .failed, .interrupted: return MacPalette.error
        case .cancelled: return MacPalette.textSecondary
        }
    }

    private func itemRow(_ item: TaskItemRecord) -> some View {
        HStack(spacing: MacSpacing.s) {
            Image(systemName: itemIcon(item.state))
                .foregroundStyle(itemTint(item.state))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(MacType.caption)
                    .lineLimit(1)
                if let message = item.failureMessage {
                    Text(message)
                        .font(MacType.caption)
                        .foregroundStyle(MacPalette.error)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: MacSpacing.s)
            if let byteCount = item.outputByteCount, byteCount > 0 {
                Text(MacModel.byteText(byteCount))
                    .font(MacType.caption)
                    .foregroundStyle(MacPalette.textTertiary)
            }
            if let vaultID = item.vaultRecordID,
               let record = model.vaultRecords.first(where: { $0.id == vaultID }) {
                Button(String(localized: "导出…", defaultValue: "导出…")) {
                    model.export(record)
                }
                .buttonStyle(.link)
                .font(MacType.caption)
            }
        }
        .padding(.horizontal, MacSpacing.m)
        .padding(.vertical, MacSpacing.xs)
    }

    private func itemIcon(_ state: ConversionItemState) -> String {
        switch state {
        case .saved: return "checkmark.circle.fill"
        case .failed, .interrupted: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle"
        case .skipped, .deferred: return "clock"
        case .pending, .converting, .saving: return "circle.dotted"
        }
    }

    private func itemTint(_ state: ConversionItemState) -> Color {
        switch state {
        case .saved: return MacPalette.success
        case .failed, .interrupted: return MacPalette.error
        default: return MacPalette.textSecondary
        }
    }
}
