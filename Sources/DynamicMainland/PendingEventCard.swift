import SwiftUI

/// 待处理事件卡片 — 设计令牌驱动，带视觉层级区分
struct PendingEventCard: View {
    let event: PendingEvent
    let viewModel: AgentViewModel
    /// 是否为键盘快捷键目标（第一个待处理事件）
    var isKeyboardTarget: Bool = false

    @State private var answerText: String = ""
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
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
        .padding(DT.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md)
                        .stroke(borderColor.opacity(isHovered ? 0.5 : 0.3), lineWidth: 1)
                )
                .shadow(color: borderColor.opacity(0.1), radius: DT.Shadow.mdRadius, y: DT.Shadow.mdY)
        )
        // 键盘目标指示：左侧发光边
        .overlay(alignment: .leading) {
            if isKeyboardTarget {
                RoundedRectangle(cornerRadius: 1)
                    .fill(borderColor)
                    .frame(width: 2)
                    .padding(.vertical, DT.Space.md)
                    .shadow(color: borderColor.opacity(0.6), radius: 4)
            }
        }
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = h }
        }
    }

    // MARK: - Permission

    private func permissionView(
        sessionId: String, requestId: String,
        agent: AgentKind, toolName: String, description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            // 头部（合并工具名称到标题行）
            HStack(spacing: DT.Space.sm) {
                RoundedRectangle(cornerRadius: DT.Space.xxs)
                    .fill(Color(hex: agent.accentColor))
                    .frame(width: 3, height: 16)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 11))
                    .foregroundStyle(DT.Accent.brand)
                Text(agent.displayName)
                    .font(DT.Font.body(.semibold))
                    .foregroundStyle(DT.Text.primary)

                Text(toolName)
                    .font(DT.Font.footnote(.bold))
                    .foregroundStyle(Color(hex: agent.accentColor))
                    .padding(.horizontal, DT.Space.sm)
                    .padding(.vertical, DT.Space.xxs)
                    .background(
                        Color(hex: agent.accentColor).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: DT.Radius.sm)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.sm)
                            .stroke(Color(hex: agent.accentColor).opacity(0.2), lineWidth: 1)
                    )

                Spacer()
            }

            // 描述
            Text(description)
                .font(DT.Font.footnote())
                .foregroundStyle(DT.Text.secondary)
                .lineLimit(3)
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, DT.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.Surface.overlay, in: RoundedRectangle(cornerRadius: DT.Radius.sm))

            // 操作按钮
            HStack(spacing: DT.Space.md) {
                Button(action: {
                    SoundManager.shared.playApproved()
                    viewModel.approvePermission(sessionId: sessionId, requestId: requestId)
                }) {
                    HStack(spacing: DT.Space.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Allow")
                            .font(DT.Font.footnote(.semibold))
                        Text("⌘Y")
                            .font(DT.Font.caption())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DT.Space.lg)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: [DT.Status.success, DT.Status.successDark],
                            startPoint: .top, endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: DT.Radius.sm)
                    )
                    .shadow(color: DT.Status.success.opacity(0.2), radius: DT.Shadow.smRadius, y: DT.Shadow.smY)
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: {
                    SoundManager.shared.playDenied()
                    viewModel.denyPermission(sessionId: sessionId, requestId: requestId)
                }) {
                    HStack(spacing: DT.Space.xs) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Deny")
                            .font(DT.Font.footnote(.semibold))
                        Text("⌘N")
                            .font(DT.Font.caption())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DT.Space.lg)
                    .padding(.vertical, 5)
                    .background(
                        DT.Status.danger.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: DT.Radius.sm)
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Spacer()
            }
        }
    }

    // MARK: - Question

    private func questionView(
        sessionId: String, requestId: String,
        agent: AgentKind, question: String, options: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            HStack(spacing: DT.Space.sm) {
                RoundedRectangle(cornerRadius: DT.Space.xxs)
                    .fill(DT.Status.info)
                    .frame(width: 3, height: 16)
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DT.Status.info)
                Text(agent.displayName)
                    .font(DT.Font.body(.semibold))
                    .foregroundStyle(DT.Text.primary)
                Text("asks")
                    .font(DT.Font.footnote())
                    .foregroundStyle(DT.Text.tertiary)
            }

            Text(question)
                .font(DT.Font.body())
                .foregroundStyle(DT.Text.secondary)
                .lineSpacing(2)

            if !options.isEmpty {
                FlowLayout(spacing: DT.Space.sm) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button(action: {
                            viewModel.answerQuestion(
                                sessionId: sessionId, requestId: requestId, answer: option
                            )
                        }) {
                            HStack(spacing: DT.Space.xs) {
                                Text("⌘\(index + 1)")
                                    .font(DT.Font.caption())
                                    .foregroundStyle(DT.Status.info.opacity(0.6))
                                Text(option)
                                    .font(DT.Font.footnote(.medium))
                                    .foregroundStyle(DT.Text.primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, DT.Space.sm)
                            .background(DT.Surface.overlay, in: RoundedRectangle(cornerRadius: DT.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: DT.Radius.sm)
                                    .stroke(DT.Status.info.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
            } else {
                HStack(spacing: DT.Space.sm) {
                    TextField("Type your answer...", text: $answerText)
                        .textFieldStyle(.plain)
                        .font(DT.Font.footnote())
                        .foregroundStyle(DT.Text.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, DT.Space.sm)
                        .background(DT.Surface.overlay, in: RoundedRectangle(cornerRadius: DT.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: DT.Radius.sm)
                                .stroke(DT.Border.default, lineWidth: 1)
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
                            .foregroundStyle(DT.Status.info)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    // MARK: - Notification

    private func notificationView(agent: AgentKind, level: String, message: String) -> some View {
        HStack(spacing: DT.Space.md) {
            Image(systemName: notificationIcon(level))
                .font(.system(size: 12))
                .foregroundStyle(notificationColor(level))
                .shadow(color: notificationColor(level).opacity(0.3), radius: 3)

            VStack(alignment: .leading, spacing: DT.Space.xxs) {
                Text(agent.displayName)
                    .font(DT.Font.footnote(.bold))
                    .foregroundStyle(DT.Text.primary)
                Text(message)
                    .font(DT.Font.footnote())
                    .foregroundStyle(DT.Text.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var cardBackground: Color {
        switch event {
        case .permissionRequest: DT.Surface.warmCard
        case .question: DT.Surface.coolCard
        case .notification(_, _, let level, _):
            switch level {
            case "error": DT.Surface.dangerCard
            case "warning": DT.Surface.warningCard
            default: DT.Surface.raised
            }
        }
    }

    private var borderColor: Color {
        switch event {
        case .permissionRequest(_, _, let agent, _, _):
            Color(hex: agent.accentColor)
        case .question:
            DT.Status.info
        case .notification:
            DT.Border.default
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
        case "success": DT.Status.success
        case "error": DT.Status.danger
        case "warning": DT.Status.warning
        default: DT.Status.info
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = DT.Space.sm

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
