import SwiftUI

/// 单个 Agent 会话行 — 设计令牌驱动
struct SessionRowView: View {
    let session: AgentSession
    let viewModel: AgentViewModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DT.Space.md) {
            // Agent 标识色条
            RoundedRectangle(cornerRadius: DT.Space.xxs)
                .fill(Color(hex: session.agent.accentColor))
                .frame(width: 3, height: 32)
                .shadow(color: Color(hex: session.agent.accentColor).opacity(0.4), radius: DT.Shadow.smRadius)

            // Agent 图标
            Image(systemName: session.agent.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: session.agent.accentColor))
                .frame(width: 24, height: 24)

            // 信息
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                HStack(spacing: DT.Space.sm) {
                    Text(session.agent.displayName)
                        .font(DT.Font.body(.semibold))
                        .foregroundStyle(DT.Text.primary)

                    Text(session.terminalApp)
                        .font(DT.Font.caption())
                        .foregroundStyle(DT.Text.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DT.Surface.raised, in: RoundedRectangle(cornerRadius: DT.Radius.xs))
                }

                HStack(spacing: DT.Space.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: statusColor.opacity(0.5), radius: 2)

                    if let action = session.currentAction {
                        Image(systemName: action.iconName)
                            .font(.system(size: 8))
                            .foregroundStyle(DT.Text.tertiary)
                        Text(action.description)
                            .font(DT.Font.caption())
                            .foregroundStyle(DT.Text.tertiary)
                            .lineLimit(1)
                    } else {
                        Text(statusText)
                            .font(DT.Font.caption())
                            .foregroundStyle(DT.Text.quaternary)
                    }
                }
            }

            Spacer()

            // 运行时间
            Text(session.elapsedTime)
                .font(DT.Font.footnote())
                .foregroundStyle(DT.Text.quaternary)

            // 跳转按钮
            Button(action: { viewModel.jumpToTerminal(sessionId: session.id) }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? DT.Text.primary : DT.Text.quaternary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(DT.Text.primary.opacity(isHovered ? 0.08 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help("Jump to terminal")
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.vertical, DT.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm)
                .fill(DT.Surface.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.sm)
                        .stroke(
                            isHovered
                                ? Color(hex: session.agent.accentColor).opacity(0.3)
                                : DT.Border.default,
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

    private var statusColor: Color {
        switch session.status {
        case .active: DT.Status.success
        case .waitingPermission: DT.Accent.brand
        case .waitingAnswer: DT.Status.info
        case .waitingPlanReview: DT.Status.purple
        case .idle: DT.Text.quaternary
        case .completed: DT.Status.success.opacity(0.5)
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
