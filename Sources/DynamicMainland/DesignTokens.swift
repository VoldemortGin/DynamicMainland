import SwiftUI

// MARK: - Design Token System

/// 统一的设计令牌系统，所有颜色、间距、字体、圆角集中管理
enum DT {

    // MARK: - Surface Colors (背景)

    enum Surface {
        /// 主背景 — 最深
        static let base = Color(hex: "#0D0D0D")
        /// 沉入背景 — 比 base 更深（底栏）
        static let sunken = Color(hex: "#0A0A0A")
        /// 浮起背景 — 卡片
        static let raised = Color(hex: "#161616")
        /// 叠加层 — 内嵌文本框/代码块
        static let overlay = Color(hex: "#111111")
        /// 权限请求卡片 — 暖色调
        static let warmCard = Color(hex: "#1C1510")
        /// 问题卡片 — 冷色调
        static let coolCard = Color(hex: "#101620")
        /// 错误通知 — 红色调
        static let dangerCard = Color(hex: "#1C1010")
        /// 警告通知 — 黄色调
        static let warningCard = Color(hex: "#1C1A10")
    }

    // MARK: - Border Colors (边框)

    enum Border {
        static let `default` = Color(hex: "#252525")
        static let subtle = Color(hex: "#1E1E1E")
        static let focus = Color(hex: "#3B82F6")
    }

    // MARK: - Text Colors (文字) — 全部通过 WCAG AA 对比度

    enum Text {
        /// 主要文字 — 柔和白（避免纯白刺眼）
        static let primary = Color(hex: "#F5F5F5")
        /// 次要文字 — 描述、正文
        static let secondary = Color(hex: "#B0B0B0")
        /// 三级文字 — 状态行、辅助信息
        static let tertiary = Color(hex: "#999999")
        /// 四级文字 — 底栏快捷键、时间戳
        static let quaternary = Color(hex: "#7A7A7A")
        /// 装饰性文字 — 版本号等非必要信息
        static let decorative = Color(hex: "#5A5A5A")
    }

    // MARK: - Accent / Brand

    enum Accent {
        static let brand = Color(hex: "#E07A52")
        static let brandDark = Color(hex: "#C4603F")
    }

    // MARK: - Status Colors (语义色)

    enum Status {
        static let success = Color(hex: "#22C55E")
        static let successDark = Color(hex: "#16A34A")
        static let danger = Color(hex: "#EF4444")
        static let warning = Color(hex: "#F59E0B")
        static let info = Color(hex: "#3B82F6")
        static let purple = Color(hex: "#A855F7")
    }

    // MARK: - Spacing (4pt 基准网格)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 内联小标签
        static let xs: CGFloat = 3
        /// 按钮、输入框、工具标签
        static let sm: CGFloat = 6
        /// 卡片
        static let md: CGFloat = 8
        /// 面板窗口
        static let lg: CGFloat = 12
    }

    // MARK: - Shadow

    enum Shadow {
        static let smRadius: CGFloat = 4
        static let smY: CGFloat = 1
        static let mdRadius: CGFloat = 8
        static let mdY: CGFloat = 2
    }

    // MARK: - Typography

    enum Font {
        static func caption(_ weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: 9, weight: weight, design: .monospaced)
        }
        static func footnote(_ weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: 10, weight: weight, design: .monospaced)
        }
        static func body(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: 11, weight: weight, design: .monospaced)
        }
        static func subheadline(_ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: 12, weight: weight, design: .monospaced)
        }
        static func headline(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: 13, weight: weight, design: .monospaced)
        }
        static func title(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: 15, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - 自定义按钮样式（带 pressed 状态反馈）

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 带 hover 高亮的按钮样式
struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : isHovered ? 1.0 : 0.9)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
