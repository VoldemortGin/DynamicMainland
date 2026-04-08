import SwiftUI

/// 主内容视图 — 深色高级感设计
struct ContentView: View {
    @Bindable var viewModel: AgentViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.2)

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
                Color(hex: "#0D0D0D")
                // 微妙的径向渐变光晕
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

    // MARK: - 顶部栏

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#E8825A"), Color(hex: "#D97757")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Dynamic Mainland")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            // 活跃会话计数器
            if !viewModel.sessions.isEmpty {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                        .shadow(color: .green.opacity(0.6), radius: 3)
                    Text("\(viewModel.sessions.count) active")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "#888888"))
                }
            }

            // 待处理事件徽章
            if !viewModel.pendingEvents.isEmpty {
                Text("\(viewModel.pendingEvents.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .shadow(color: .red.opacity(0.4), radius: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 底部状态栏

    private var footerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 9))
                .foregroundStyle(Color(hex: "#555555"))
            Text("⌥D toggle · ⌘Y allow · ⌘N deny")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "#555555"))
            Spacer()
            Text("v0.1.0")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(hex: "#333333"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(hex: "#0A0A0A"))
    }

    // MARK: - 会话列表

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 6) {
                // 待处理事件优先
                ForEach(viewModel.pendingEvents) { event in
                    PendingEventCard(event: event, viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .push(from: .top).combined(with: .opacity),
                            removal: .push(from: .bottom).combined(with: .opacity)
                        ))
                }

                // 活跃会话
                ForEach(viewModel.sessions) { session in
                    SessionRowView(session: session, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.sessions.count)
        .animation(.easeInOut(duration: 0.2), value: viewModel.pendingEvents.count)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                // 脉冲动画圈
                Circle()
                    .stroke(Color(hex: "#333333"), lineWidth: 1)
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(Color(hex: "#222222"), lineWidth: 1)
                    .frame(width: 90, height: 90)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: "#444444"))
            }

            Text("Waiting for agents...")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "#666666"))

            Text("启动 AI 编码代理后，会话将自动出现")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: "#444444"))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - 安装引导

    private var setupPrompt: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "#D97757"))
                .shadow(color: Color(hex: "#D97757").opacity(0.3), radius: 8)

            Text("Install Hooks")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text("需要在 AI Agent 配置中安装 hook\n才能监控和控制代理操作")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: "#888888"))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button(action: { viewModel.installHooks() }) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("一键安装")
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#D97757"), Color(hex: "#C4603F")],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .shadow(color: Color(hex: "#D97757").opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding()
    }
}
