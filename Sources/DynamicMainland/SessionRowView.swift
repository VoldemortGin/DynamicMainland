import SwiftUI

/// 单个 Agent 会话行 — 深色卡片风格
struct SessionRowView: View {
    let session: AgentSession
    let viewModel: AgentViewModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Agent 标识色条
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: session.agent.accentColor))
                .frame(width: 3, height: 32)
                .shadow(color: Color(hex: session.agent.accentColor).opacity(0.4), radius: 4)

            // Agent 图标
            Image(systemName: session.agent.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: session.agent.accentColor))
                .frame(width: 24, height: 24)

            // 信息
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.agent.displayName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    Text(session.terminalApp)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "#666666"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(hex: "#1A1A1A"), in: RoundedRectangle(cornerRadius: 3))
                }

                HStack(spacing: 4) {
                    statusDot
                    if let action = session.currentAction {
                        Image(systemName: action.iconName)
                            .font(.system(size: 8))
                            .foregroundStyle(Color(hex: "#888888"))
                        Text(action.description)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: "#888888"))
                            .lineLimit(1)
                    } else {
                        Text(statusText)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: "#666666"))
                    }
                }
            }

            Spacer()

            // 运行时间
            Text(session.elapsedTime)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "#555555"))

            // 跳转按钮
            Button(action: { viewModel.jumpToTerminal(sessionId: session.id) }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? .white : Color(hex: "#555555"))
            }
            .buttonStyle(.plain)
            .help("跳转到终端")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#1A1A1A"))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isHovered
                                ? Color(hex: session.agent.accentColor).opacity(0.3)
                                : Color(hex: "#2A2A2A"),
                            lineWidth: 1
                        )
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 5, height: 5)
            .shadow(color: statusColor.opacity(0.5), radius: 2)
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .waitingPermission: .orange
        case .waitingAnswer: Color(hex: "#3B82F6")
        case .waitingPlanReview: Color(hex: "#A855F7")
        case .idle: Color(hex: "#555555")
        case .completed: .green.opacity(0.5)
        }
    }

    private var statusText: String {
        switch session.status {
        case .active: "running"
        case .waitingPermission: "awaiting permission"
        case .waitingAnswer: "awaiting answer"
        case .waitingPlanReview: "plan review"
        case .idle: "idle"
        case .completed: "done — click to jump"
        }
    }
}
