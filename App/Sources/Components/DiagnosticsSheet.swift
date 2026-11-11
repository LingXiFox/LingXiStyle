import SwiftUI

struct DiagnosticsSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m)
            }
            .background(Palette.background)
            .navigationTitle("诊断信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: text) {
                    Label("分享诊断信息", systemImage: "square.and.arrow.up")
                        .font(Typography.bodyEmphasized)
                        .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xs)
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
        .duoFormWidth()
    }
}
