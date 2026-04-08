import SwiftUI

/// 主内容视图 — 深色高级感设计，使用统一设计令牌
struct ContentView: View {
    @Bindable var viewModel: AgentViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.15)

            if !viewModel.hooksInstalled {
                setupPrompt
            } else if viewModel.sessions.isEmpty && viewModel.pendingEvents.isEmpty {
                emptyState
            } else {
                sessionList
            }

            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                DT.Surface.base
                RadialGradient(
                    colors: [Color(hex: "#1a2332").opacity(0.4), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 300
                )
            }
        )
        .preferredColorScheme(.dark)
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
            Text("⌥D toggle · ⌘Y allow · ⌘N deny")
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
                        isKeyboardTarget: event.id == viewModel.pendingEvents.first?.id
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
        .animation(.spring(duration: 0.3, bounce: 0.15), value: viewModel.sessions.count)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: viewModel.pendingEvents.count)
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
                    .symbolEffect(.pulse, options: .repeating)
            }

            VStack(spacing: DT.Space.md) {
                Text("Waiting for agents...")
                    .font(DT.Font.headline(.medium))
                    .foregroundStyle(DT.Text.tertiary)

                Text("Run claude, codex, or cursor in terminal")
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

            Spacer()
        }
        .padding()
    }
}

// MARK: - 脉冲圆点

struct PulsingDot: View {
    let color: Color
    let size: CGFloat

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(isPulsing ? 0.7 : 0.3), radius: isPulsing ? 4 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
