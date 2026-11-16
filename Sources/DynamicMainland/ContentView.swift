import SwiftUI

/// 主内容视图 — 深色高级感设计，使用统一设计令牌
struct ContentView: View {
    @Bindable var viewModel: AgentViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.15)

            if !viewModel.sessions.isEmpty || !viewModel.pendingEvents.isEmpty {
                // 有会话或待处理事件时优先显示，即使 hooks 未安装（如手动接入的 agent）
                sessionList
            } else if !viewModel.hooksInstalled || viewModel.installFeedback != nil {
                // 安装结果提示期间保留安装页，让结果显示在按钮下方
                setupPrompt
            } else {
                emptyState
            }

            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
        .preferredColorScheme(.dark)
    }

    // MARK: - Panel Background

    /// 面板最外层背景：macOS 26+ 用系统玻璃材质（Liquid Glass），
    /// 低版本或开启「降低透明度」时回退到原有不透明背景
    @ViewBuilder
    private var panelBackground: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                // 玻璃之上保留一层半透明底色，保证小号等宽文字的对比度
                DT.Surface.base.opacity(0.65)
                backgroundGradient
            }
        } else {
            ZStack {
                DT.Surface.base
                backgroundGradient
            }
        }
    }

    private var backgroundGradient: some View {
        RadialGradient(
            colors: [Color(hex: "#1a2332").opacity(0.4), .clear],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 300
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: DT.Space.md) {
            // Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DT.Accent.brand, DT.Accent.brandDark],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Dynamic Mainland")
                .font(DT.Font.headline())
                .foregroundStyle(DT.Text.primary)

            Spacer()

            // 活跃会话计数
            if !viewModel.sessions.isEmpty {
                HStack(spacing: DT.Space.xs) {
                    PulsingDot(color: DT.Status.success, size: 5)
                    Text("\(viewModel.sessions.count) active")
                        .font(DT.Font.footnote())
                        .foregroundStyle(DT.Text.tertiary)
                }
            }

            // 待处理事件徽章
            if !viewModel.pendingEvents.isEmpty {
                Text("\(viewModel.pendingEvents.count)")
                    .font(DT.Font.caption(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DT.Space.sm)
                    .padding(.vertical, DT.Space.xxs)
                    .background(DT.Status.danger, in: Capsule())
                    .shadow(color: DT.Status.danger.opacity(0.4), radius: DT.Shadow.smRadius)
            }
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.vertical, DT.Space.md)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "keyboard")
                .font(.system(size: 9))
                .foregroundStyle(DT.Text.quaternary)
            Text("⌃⇧D toggle · ⌃⇧Y allow · ⌃⇧N deny")
                .font(DT.Font.caption())
                .foregroundStyle(DT.Text.quaternary)
            Spacer()
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.vertical, DT.Space.sm)
        .background(DT.Surface.sunken)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: DT.Space.md) {
                // 待处理事件（优先）
                ForEach(viewModel.pendingEvents) { event in
                    PendingEventCard(
                        event: event,
                        viewModel: viewModel,
                        isKeyboardTarget: event.id == (viewModel.firstPermissionRequest?.requestId
                            ?? viewModel.pendingEvents.first?.id)
                    )
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .push(from: .bottom).combined(with: .opacity)
                    ))
                }

                // 分区标题
                if !viewModel.pendingEvents.isEmpty && !viewModel.sessions.isEmpty {
                    HStack {
                        Text("SESSIONS")
                            .font(DT.Font.caption(.bold))
                            .foregroundStyle(DT.Text.quaternary)
                            .tracking(1.5)
                        Spacer()
                    }
                    .padding(.horizontal, DT.Space.xs)
                    .padding(.top, DT.Space.xs)
                }

                // 活跃会话
                ForEach(viewModel.sessions) { session in
                    SessionRowView(session: session, viewModel: viewModel)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, DT.Space.lg)
            .padding(.vertical, DT.Space.md)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: viewModel.sessions.count)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: viewModel.pendingEvents.count)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DT.Space.xl) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(DT.Border.default, lineWidth: 1)
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(DT.Border.subtle, lineWidth: 1)
                    .frame(width: 90, height: 90)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundStyle(DT.Text.quaternary)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            }

            VStack(spacing: DT.Space.md) {
                Text("Waiting for agents...")
                    .font(DT.Font.headline(.medium))
                    .foregroundStyle(DT.Text.tertiary)

                Text("Run Claude Code (claude) in a terminal")
                    .font(DT.Font.body())
                    .foregroundStyle(DT.Text.quaternary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Setup Prompt

    private var setupPrompt: some View {
        VStack(spacing: DT.Space.xxl) {
            Spacer()

            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 32))
                .foregroundStyle(DT.Accent.brand)
                .shadow(color: DT.Accent.brand.opacity(0.3), radius: DT.Shadow.mdRadius)

            VStack(spacing: DT.Space.md) {
                Text("Install Hooks")
                    .font(DT.Font.title())
                    .foregroundStyle(DT.Text.primary)

                Text("Install hooks in AI agent configs\nto monitor and control operations")
                    .font(DT.Font.body())
                    .foregroundStyle(DT.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button(action: { viewModel.installHooks() }) {
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "bolt.fill")
                    Text("Install Now")
                }
                .font(DT.Font.subheadline())
                .foregroundStyle(.white)
                .padding(.horizontal, DT.Space.xxl)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [DT.Accent.brand, DT.Accent.brandDark],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: DT.Radius.sm)
                )
                .shadow(color: DT.Accent.brand.opacity(0.3), radius: DT.Shadow.smRadius, y: DT.Shadow.smY)
            }
            .buttonStyle(ScaleButtonStyle())

            if let feedback = viewModel.installFeedback {
                installFeedbackView(feedback)
            }

            Spacer()
        }
        .padding()
    }

    private func installFeedbackView(_ feedback: InstallFeedback) -> some View {
        let succeeded = feedback.error == nil
        return HStack(alignment: .top, spacing: DT.Space.xs) {
            Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(feedback.message)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .font(DT.Font.footnote())
        .foregroundStyle(succeeded ? DT.Status.success : DT.Status.danger)
        .padding(.horizontal, DT.Space.lg)
    }
}

// MARK: - 脉冲圆点

/// 运行中状态点的"呼吸"效果：用 Core Animation 图层动画（opacity + scale）实现，
/// 由渲染服务器合成，不会像 SwiftUI repeatForever 动画那样每帧驱动视图更新
struct PulsingDot: NSViewRepresentable {
    let color: Color
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let animationKey = "pulse"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        // 用居中锚点的子图层做缩放，NSView 自带图层的锚点在左下角
        let dot = CALayer()
        dot.frame = CGRect(x: 0, y: 0, width: size, height: size)
        dot.cornerRadius = size / 2
        view.layer?.addSublayer(dot)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let dot = view.layer?.sublayers?.first else { return }
        dot.backgroundColor = NSColor(color).cgColor

        if reduceMotion {
            dot.removeAnimation(forKey: Self.animationKey)
        } else if dot.animation(forKey: Self.animationKey) == nil {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.4
            opacity.toValue = 1
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.85
            scale.toValue = 1.15

            let group = CAAnimationGroup()
            group.animations = [opacity, scale]
            group.duration = 2
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: Self.animationKey)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}
