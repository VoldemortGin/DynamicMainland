import SwiftUI

/// 待处理事件卡片 — 深色主题，带 Agent 专属色高亮
struct PendingEventCard: View {
    let event: PendingEvent
    let viewModel: AgentViewModel

    @State private var answerText: String = ""
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch event {
            case .permissionRequest(let sessionId, let requestId, let agent, let toolName, let description):
                permissionView(
                    sessionId: sessionId, requestId: requestId,
                    agent: agent, toolName: toolName, description: description
                )

            case .question(let sessionId, let requestId, let agent, let question, let options):
                questionView(
                    sessionId: sessionId, requestId: requestId,
                    agent: agent, question: question, options: options
                )

            case .notification(_, let agent, let level, let message):
                notificationView(agent: agent, level: level, message: message)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#1A1A1A"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor.opacity(isHovered ? 0.5 : 0.25), lineWidth: 1)
                )
                .shadow(color: borderColor.opacity(0.1), radius: 8, y: 2)
        )
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = h }
        }
    }

    // MARK: - 权限请求

    private func permissionView(
        sessionId: String, requestId: String,
        agent: AgentKind, toolName: String, description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: agent.accentColor))
                    .frame(width: 3, height: 16)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(agent.displayName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("requests permission")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: "#888888"))
                Spacer()
            }

            // 工具名称标签
            HStack(spacing: 6) {
                Text(toolName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: agent.accentColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color(hex: agent.accentColor).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: agent.accentColor).opacity(0.2), lineWidth: 1)
                    )
            }

            // 描述
            Text(description)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#AAAAAA"))
                .lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#111111"), in: RoundedRectangle(cornerRadius: 6))

            // 操作按钮
            HStack(spacing: 8) {
                Button(action: {
                    SoundManager.shared.playApproved()
                    viewModel.approvePermission(sessionId: sessionId, requestId: requestId)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Allow")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        Text("⌘Y")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#22C55E"), Color(hex: "#16A34A")],
                            startPoint: .top, endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .shadow(color: Color(hex: "#22C55E").opacity(0.2), radius: 4, y: 1)
                }
                .buttonStyle(.plain)

                Button(action: {
                    SoundManager.shared.playDenied()
                    viewModel.denyPermission(sessionId: sessionId, requestId: requestId)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Deny")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        Text("⌘N")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Color(hex: "#DC2626").opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }

    // MARK: - 问题

    private func questionView(
        sessionId: String, requestId: String,
        agent: AgentKind, question: String, options: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#3B82F6"))
                    .frame(width: 3, height: 16)
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#3B82F6"))
                Text(agent.displayName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("asks")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: "#888888"))
            }

            Text(question)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: "#E5E5E5"))
                .lineSpacing(2)

            if !options.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button(action: {
                            viewModel.answerQuestion(
                                sessionId: sessionId, requestId: requestId, answer: option
                            )
                        }) {
                            HStack(spacing: 4) {
                                Text("⌘\(index + 1)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(Color(hex: "#3B82F6").opacity(0.6))
                                Text(option)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#111111"), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "#3B82F6").opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    TextField("输入回答...", text: $answerText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#111111"), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(hex: "#333333"), lineWidth: 1)
                        )

                    Button(action: {
                        guard !answerText.isEmpty else { return }
                        viewModel.answerQuestion(
                            sessionId: sessionId, requestId: requestId, answer: answerText
                        )
                        answerText = ""
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "#3B82F6"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 通知

    private func notificationView(agent: AgentKind, level: String, message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: notificationIcon(level))
                .font(.system(size: 12))
                .foregroundStyle(notificationColor(level))
                .shadow(color: notificationColor(level).opacity(0.3), radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: "#AAAAAA"))
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    // MARK: - 辅助

    private var borderColor: Color {
        switch event {
        case .permissionRequest(_, _, let agent, _, _):
            Color(hex: agent.accentColor)
        case .question:
            Color(hex: "#3B82F6")
        case .notification:
            Color(hex: "#333333")
        }
    }

    private func notificationIcon(_ level: String) -> String {
        switch level {
        case "success": "checkmark.circle.fill"
        case "error": "exclamationmark.triangle.fill"
        case "warning": "exclamationmark.circle.fill"
        default: "info.circle.fill"
        }
    }

    private func notificationColor(_ level: String) -> Color {
        switch level {
        case "success": Color(hex: "#22C55E")
        case "error": Color(hex: "#EF4444")
        case "warning": Color(hex: "#F59E0B")
        default: Color(hex: "#3B82F6")
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize, subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
