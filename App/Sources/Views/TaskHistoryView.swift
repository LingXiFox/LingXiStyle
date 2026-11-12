import SwiftUI
import LingXiKit

/// Task history backed by the on-disk journal: every conversion run keeps its item states,
/// quota settlement and vault pointer after relaunch.
struct TaskHistoryView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void
    var controlInset: CGFloat = 0

    var body: some View {
        NavigationStack {
            TaskHistoryContent(model: model, controlInset: controlInset)
                .navigationTitle(String(localized: "history.title", defaultValue: "任务历史"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成")) { onClose() }
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(Palette.accentText)
                            .accessibilityIdentifier("history.done")
                    }
                }
        }
    }
}

/// History body without navigation chrome so it can also be pushed from Settings.
struct TaskHistoryContent: View {
    @ObservedObject var model: AppModel
    var controlInset: CGFloat = 0

    @State private var expandedTaskID: UUID?
    @State private var resavingID: UUID?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            AmbientBackdrop(intensity: .quiet)

            ScrollView {
                VStack(spacing: Spacing.s) {
                    if model.history.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.history) { task in
                            taskCard(task)
                        }
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xl + controlInset)
                .frame(maxWidth: Layout.iPadContentMaxWidth)
            }
        }
        .navigationTitle(String(localized: "history.title", defaultValue: "任务历史"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refreshHistory() }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Palette.textTertiary)
            Text(String(localized: "history.empty.title", defaultValue: "还没有任务记录"))
                .font(Typography.bodyEmphasized)
                .foregroundStyle(Palette.textPrimary)
            Text(String(localized: "history.empty.message",
                        defaultValue: "每次转换完成后，这里会记录张数、状态和结果，方便回头查看。"))
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Task card

    private func taskCard(_ task: ConversionTaskRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button {
                withAnimation(Motion.selection) {
                    expandedTaskID = expandedTaskID == task.id ? nil : task.id
                }
            } label: {
                HStack(alignment: .top, spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.dateText(task.createdAt))
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(Palette.textPrimary)
                        Text(summaryText(task))
                            .font(Typography.micro)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    stateChip(task.state)
                    Image(systemName: expandedTaskID == task.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedTaskID == task.id {
                Divider().overlay(Palette.hairline)
                VStack(spacing: Spacing.xs) {
                    ForEach(task.items) { item in
                        itemRow(item)
                    }
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func itemRow(_ item: TaskItemRecord) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: Self.icon(for: item.state))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.color(for: item.state))
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if item.isLivePhoto {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.accentText)
                    }
                }
                if let message = item.failureMessage, !message.isEmpty {
                    Text(message)
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if item.state == .saved, let bytes = item.outputByteCount {
                    Text(AppModel.byteText(bytes))
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Spacer(minLength: 0)

            if let vaultID = item.vaultRecordID, let record = model.vaultRecord(id: vaultID) {
                Button {
                    resave(record, item: item)
                } label: {
                    if resavingID == item.id {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(String(localized: "history.resave", defaultValue: "重新保存"))
                            .font(Typography.micro)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accentText)
                .disabled(resavingID != nil)
            } else {
                Text(Self.stateText(item.state))
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func resave(_ record: VaultRecord, item: TaskItemRecord) {
        resavingID = item.id
        Task {
            await model.resaveFromVault(record)
            resavingID = nil
        }
    }

    // MARK: - Copy helpers

    private func summaryText(_ task: ConversionTaskRecord) -> String {
        var parts: [String] = []
        if task.savedCount > 0 {
            parts.append(String(localized: "history.savedCount", defaultValue: "成功 \(task.savedCount)"))
        }
        if task.failedCount > 0 {
            parts.append(String(localized: "history.failedCount", defaultValue: "失败 \(task.failedCount)"))
        }
        if task.cancelledCount > 0 {
            parts.append(String(localized: "history.cancelledCount", defaultValue: "取消 \(task.cancelledCount)"))
        }
        if parts.isEmpty {
            parts.append(String(localized: "history.itemCount", defaultValue: "\(task.items.count) 张"))
        }
        if task.totalByteCount > 0 {
            parts.append(AppModel.byteText(task.totalByteCount))
        }
        return parts.joined(separator: " · ")
    }

    private func stateChip(_ state: ConversionTaskState) -> some View {
        Text(Self.title(for: state))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Self.color(for: state))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Self.color(for: state).opacity(0.12), in: Capsule())
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - State mapping

    private static func title(for state: ConversionTaskState) -> String {
        switch state {
        case .running:
            return String(localized: "task.state.running", defaultValue: "处理中")
        case .waitingToSave:
            return String(localized: "task.state.waitingToSave", defaultValue: "待保存")
        case .completed:
            return String(localized: "task.state.completed", defaultValue: "已完成")
        case .partiallyCompleted:
            return String(localized: "task.state.partiallyCompleted", defaultValue: "部分完成")
        case .failed:
            return String(localized: "task.state.failed", defaultValue: "失败")
        case .cancelled:
            return String(localized: "task.state.cancelled", defaultValue: "已取消")
        case .interrupted:
            return String(localized: "task.state.interrupted", defaultValue: "已中断")
        }
    }

    private static func color(for state: ConversionTaskState) -> Color {
        switch state {
        case .running, .waitingToSave:
            return Palette.info
        case .completed:
            return Palette.success
        case .partiallyCompleted:
            return Palette.warning
        case .failed:
            return Palette.error
        case .cancelled, .interrupted:
            return Palette.textSecondary
        }
    }

    private static func stateText(_ state: ConversionItemState) -> String {
        switch state {
        case .pending:
            return String(localized: "item.state.pending", defaultValue: "排队中")
        case .converting:
            return String(localized: "item.state.converting", defaultValue: "处理中")
        case .saving:
            return String(localized: "item.state.saving", defaultValue: "保存中")
        case .saved:
            return String(localized: "item.state.saved", defaultValue: "已保存")
        case .failed:
            return String(localized: "item.state.failed", defaultValue: "失败")
        case .cancelled:
            return String(localized: "item.state.cancelled", defaultValue: "已取消")
        case .skipped:
            return String(localized: "item.state.skipped", defaultValue: "已跳过")
        case .deferred:
            return String(localized: "item.state.deferred", defaultValue: "待额度")
        case .interrupted:
            return String(localized: "item.state.interrupted", defaultValue: "已中断")
        }
    }

    private static func icon(for state: ConversionItemState) -> String {
        switch state {
        case .saved:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .cancelled, .interrupted:
            return "minus.circle"
        case .skipped, .deferred:
            return "forward.circle"
        case .pending, .converting, .saving:
            return "circle.dotted"
        }
    }

    private static func color(for state: ConversionItemState) -> Color {
        switch state {
        case .saved:
            return Palette.success
        case .failed:
            return Palette.error
        case .pending, .converting, .saving:
            return Palette.info
        case .cancelled, .interrupted, .skipped, .deferred:
            return Palette.textTertiary
        }
    }
}
