import SwiftUI
import LingXiKit

/// 1.8.1 tutorial: a short, step-by-step onboarding instead of a single manual page.
/// Each step pairs one large illustration with one or two lines of copy; the Live Photo
/// default is configured in place, and the quota / compatibility details come last.
struct TutorialView: View {
    @ObservedObject var model: AppModel
    var isFirstRun: Bool
    var onClose: () -> Void

    @Environment(\.contentMargin) private var margin
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stepIndex = 0
    @State private var scrollTarget: Int?

    private var steps: [TutorialStep] { TutorialStep.all }
    private var maxContentWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 560 : 640 }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    stepCounter
                    pager
                    bottomBar
                }
            }
            .duoSheetWidth()
            .navigationTitle(String(localized: "tutorial.title", defaultValue: "使用教程"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isLastStep {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Palette.fillControl, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "tutorial.close", defaultValue: "关闭教程"))
                    .accessibilityIdentifier("tutorial.done")
                }
                }
            }
        }
        .accessibilityIdentifier("tutorial.root")
    }

    // MARK: Pager

    private var stepCounter: some View {
        Text("\(stepIndex + 1) / \(steps.count)")
            .font(Typography.micro)
            .foregroundStyle(Palette.textTertiary)
            .monospacedDigit()
            .padding(.top, Spacing.s)
            .accessibilityHidden(true)
    }

    private var pager: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        page(step)
                            .frame(width: proxy.size.width)
                            .id(index)
                            .accessibilityHidden(index != stepIndex)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollTarget)
            .scrollIndicators(.hidden)
            .onChange(of: stepIndex) { _, newValue in
                guard scrollTarget != newValue else { return }
                withAnimation(Motion.respectingReduceMotion(reduceMotion, Motion.selection)) {
                    scrollTarget = newValue
                }
            }
            .onChange(of: scrollTarget) { _, newValue in
                guard let newValue, newValue != stepIndex else { return }
                stepIndex = newValue
            }
        }
    }

    private func page(_ step: TutorialStep) -> some View {
        GeometryReader { proxy in
            ScrollView {
            VStack(spacing: proxy.size.height < 450 ? Spacing.s : Spacing.m) {
                TutorialIllustration(kind: step.kind)
                    .frame(height: illustrationHeight(for: step.kind, available: proxy.size.height))

                VStack(spacing: proxy.size.height < 450 ? Spacing.xs : Spacing.s) {
                    Text(step.title)
                        .font(Typography.section)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tutorial.step.\(step.id).title")

                    Text(step.body)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = step.note {
                        noteView(note)
                    }

                    accessory(for: step.kind)
                }
                .frame(maxWidth: maxContentWidth)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, margin)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.l)
            .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tutorial.step.\(step.id)")
        }
    }

    private func illustrationHeight(for kind: TutorialStepKind, available: CGFloat) -> CGFloat {
        let isCompactHeight = available < 450
        if dynamicTypeSize.isAccessibilitySize {
            switch kind {
            case .livePhoto, .quota:
                return 100
            default:
                return 140
            }
        }
        if isCompactHeight {
            switch kind {
            case .livePhoto, .quota:
                return 100
            default:
                return 180
            }
        }
        switch kind {
        case .livePhoto, .quota:
            return 190
        default:
            return 230
        }
    }

    // MARK: Step accessories

    @ViewBuilder
    private func accessory(for kind: TutorialStepKind) -> some View {
        switch kind {
        case .livePhoto:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(String(localized: "settings.livePhoto.section", defaultValue: "实况照片处理方式"))
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(Palette.textSecondary)
                LivePhotoModeSelector(
                    selection: model.livePhotoModePreference,
                    onSelect: { model.setLivePhotoModePreference($0) },
                    scopeNote: String(localized: "tutorial.livePhoto.scope", defaultValue: "这里保存默认值；每次处理前仍然可以临时切换。"),
                    showsDetails: false
                )
            }
            .padding(.top, Spacing.xxs)

        case .quota:
            VStack(spacing: Spacing.s) {
                HStack(alignment: .center, spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.accentText)
                        .accessibilityHidden(true)
                    Text(String(format: String(localized: "tutorial.defaultMode", defaultValue: "默认：%@"), model.livePhotoModePreference.title))
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

                Label(String(localized: "tutorial.privacy", defaultValue: "不需要登录，不联网，也不要求无关权限。照片只在本机处理。"),
                      systemImage: "lock.shield")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Spacing.xxs)

        default:
            EmptyView()
        }
    }

    private func noteView(_ note: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.info)
                .accessibilityHidden(true)
            Text(note)
                .font(Typography.caption)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .background(Palette.fillControl, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Spacing.s) {
            pageDots

            HStack(spacing: Spacing.s) {
                if stepIndex > 0 {
                    backButton
                }

                PrimaryActionButton(title: primaryTitle,
                                   systemImage: isLastStep ? nil : "arrow.right") {
                    advance()
                }
                .accessibilityIdentifier("tutorial.primary")
            }

            if isFirstRun && !isLastStep {
                Button(action: onClose) {
                    Text(String(localized: "tutorial.skip", defaultValue: "跳过"))
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: Layout.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tutorial.skip")
            }
        }
        .padding(.top, Spacing.s)
        .padding(.horizontal, margin)
        .padding(.bottom, Spacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.5)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == stepIndex ? Palette.accent : Palette.fillControl)
                    .frame(width: index == stepIndex ? 16 : 6, height: 6)
            }
        }
        .animation(Motion.respectingReduceMotion(reduceMotion, Motion.selection), value: stepIndex)
        .accessibilityHidden(true)
    }

    private var backButton: some View {
        Button {
            goBack()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(String(localized: "tutorial.back", defaultValue: "上一步"))
                }
            }
            .font(Typography.bodyEmphasized)
            .foregroundStyle(Palette.textPrimary)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 52 : 104, height: Layout.primaryButtonHeight)
            .background(Palette.fillControl, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "tutorial.back", defaultValue: "上一步"))
        .accessibilityIdentifier("tutorial.back")
    }

    private var primaryTitle: String {
        if !isLastStep {
            return String(localized: "tutorial.next", defaultValue: "下一步")
        }
        return isFirstRun
            ? String(localized: "tutorial.start", defaultValue: "开始使用")
            : String(localized: "完成")
    }

    private func advance() {
        guard !isLastStep else {
            onClose()
            return
        }
        withAnimation(Motion.respectingReduceMotion(reduceMotion, Motion.selection)) {
            stepIndex += 1
        }
    }

    private func goBack() {
        guard stepIndex > 0 else { return }
        withAnimation(Motion.respectingReduceMotion(reduceMotion, Motion.selection)) {
            stepIndex -= 1
        }
    }
}

// MARK: - Content model

enum TutorialStepKind: String {
    case layers
    case styles
    case compatibility
    case pick
    case livePhoto
    case result
    case edit
    case invisible
    case quota
}

struct TutorialStep: Identifiable {
    let kind: TutorialStepKind
    let title: String
    let body: String
    var note: String?

    var id: String { kind.rawValue }

    /// Nine short stops. The twelve required topics are folded in: what Texel is and how the
    /// original relates to the new photo (layers), Styles plus texture/grain (styles),
    /// suitable photos and incompatible cases (compatibility), picking and starting (pick),
    /// the Live Photo default and its one-slot rule (livePhoto), finding the result (result),
    /// Style editing and grain (edit), why it can look unchanged (invisible), quota and Pro.
    static var all: [TutorialStep] {
        [
            TutorialStep(
                kind: .layers,
                title: String(localized: "tutorial.step.layers.title", defaultValue: "一层质感，原片不动"),
                body: String(localized: "tutorial.step.layers.body", defaultValue: "纹粒只给 HEIC 原片追加纹理与颗粒，再另存一张新照片。像素不重绘、不转码。")
            ),
            TutorialStep(
                kind: .styles,
                title: String(localized: "tutorial.step.styles.title", defaultValue: "摄影风格，还能继续调"),
                body: String(localized: "tutorial.step.styles.body", defaultValue: "iPhone 16 / 17 的摄影风格能调强度与纹理颗粒，第二代、第三代风格都适用。新照片之后仍可回到这里继续调。")
            ),
            TutorialStep(
                kind: .compatibility,
                title: String(localized: "tutorial.step.compatibility.title", defaultValue: "哪些照片能处理"),
                body: String(localized: "tutorial.step.compatibility.body", defaultValue: "iPhone 16 / 17 的 HEIC 最合适。非 HEIF、RAW、已带纹理，或缺少配对视频的实况照片会跳过，并说明原因。"),
                note: String(localized: "tutorial.step.compatibility.note", defaultValue: "共享相册里的照片，先保存到图库再试。")
            ),
            TutorialStep(
                kind: .pick,
                title: String(localized: "tutorial.step.pick.title", defaultValue: "选照片，点开始"),
                body: String(localized: "tutorial.step.pick.body", defaultValue: "从图库选 HEIC 或实况照片，也可以从「文件」导入。点「添加纹理与颗粒」，读取、追加、校验、保存都会真实显示。")
            ),
            TutorialStep(
                kind: .livePhoto,
                title: String(localized: "tutorial.step.livePhoto.title", defaultValue: "实况照片，只算一张"),
                body: String(localized: "tutorial.step.livePhoto.body", defaultValue: "只处理主帧更快；完整处理会让动态画面也带上同样的质感。")
            ),
            TutorialStep(
                kind: .result,
                title: String(localized: "tutorial.step.result.title", defaultValue: "新照片在哪里"),
                body: String(localized: "tutorial.step.result.body", defaultValue: "完成后打开「照片」→「最近项目」，文件名带 _Texel。原图、原实况照片和已有编辑都不会被覆盖。")
            ),
            TutorialStep(
                kind: .edit,
                title: String(localized: "tutorial.step.edit.title", defaultValue: "想再调风格"),
                body: String(localized: "tutorial.step.edit.body", defaultValue: "打开新照片 → 编辑 → 摄影风格，拖动强度滑块，纹理与颗粒会一起变化。")
            ),
            TutorialStep(
                kind: .invisible,
                title: String(localized: "tutorial.step.invisible.title", defaultValue: "看不出变化？"),
                body: String(localized: "tutorial.step.invisible.body", defaultValue: "纹理与颗粒是单独一层，缩略图和部分旧系统会忽略它。放大查看，或进入编辑面板就能看到。")
            ),
            TutorialStep(
                kind: .quota,
                title: String(localized: "tutorial.step.quota.title", defaultValue: "额度与 Pro"),
                body: String(localized: "tutorial.step.quota.body", defaultValue: "每天 5 张免费额度，成功保存才扣 1 张；每张实况照片也只算 1 张。Pro 一次购买，永久不限张数。")
            )
        ]
    }
}
