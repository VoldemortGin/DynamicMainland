import AppKit
import SwiftUI

/// 刘海区域的浮动面板 — 深色圆角，非激活式
final class NotchPanel: NSPanel {
    private static let panelWidth: CGFloat = 380
    /// 最小高度：够放 header + 空状态 + footer
    private static let minHeight: CGFloat = 300
    /// 最大高度上限（还会受所在屏幕可用高度限制）
    private static let maxHeightCap: CGFloat = 640
    /// 面板顶边与刘海 / 菜单栏的间距
    private static let topMargin: CGFloat = 4
    /// 面板底边与屏幕可用区域底部的最小间距
    private static let bottomMargin: CGFloat = 8

    /// SwiftUI 上报的内容理想高度（未上报前用旧的固定高度）
    private var idealHeight: CGFloat = 440
    /// 逻辑上的显示状态（淡出动画期间 isVisible 仍为 true）
    private(set) var isPresented = false
    /// 当前显示是否由新到的权限请求 / 提问自动弹出（用户手动切换过即为 false）
    private(set) var isAutoPresented = false

    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        // 点击按钮不成为 key window，键盘焦点留在原先的 App；只有文本框等需要键盘输入的控件才让面板成为 key
        self.becomesKeyOnlyIfNeeded = true

        // 圆角和边框
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12  // DT.Radius.lg
        self.contentView?.layer?.masksToBounds = true
        self.contentView?.layer?.borderWidth = 1
        self.contentView?.layer?.borderColor = NSColor(white: 0.15, alpha: 0.5).cgColor

        // 插拔显示器/合盖/改分辨率后重新定位
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        positionNearNotch()
    }

    @objc private func screenParametersDidChange() {
        if isVisible {
            positionNearNotch()
        }
    }

    /// 内容理想高度变化：顶边不动，向下伸缩；变化 <1pt 忽略，避免布局抖动
    func updateIdealHeight(_ height: CGFloat) {
        guard abs(height - idealHeight) >= 1 else { return }
        idealHeight = height
        // show() 在上屏前会先同步布局触发上报，此时 isVisible 仍为 false，须以 isPresented 一并判断；
        // 尚未上屏时直接定高、不做动画，避免淡入的同时出现高度收缩
        guard isVisible || isPresented else { return }
        let animate = isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        positionNearNotch(animate: animate)
    }

    func positionNearNotch(animate: Bool = false) {
        // 优先选带刘海的屏幕，没有则回退到主屏
        let notchScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notchScreen ?? NSScreen.main else { return }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let hasNotch = screen.safeAreaInsets.top > 0

        let top: CGFloat
        if hasNotch {
            top = screenFrame.maxY - screen.safeAreaInsets.top - Self.topMargin
        } else {
            top = visibleFrame.maxY - Self.topMargin
        }
        let maxHeight = max(Self.minHeight, min(Self.maxHeightCap, top - visibleFrame.minY - Self.bottomMargin))
        let panelHeight = min(max(idealHeight, Self.minHeight), maxHeight).rounded()

        let target = NSRect(
            x: screenFrame.midX - Self.panelWidth / 2,
            y: top - panelHeight,
            width: Self.panelWidth,
            height: panelHeight
        )
        guard target != frame else { return }
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
    }

    /// 文本输入结束后把键盘焦点还给前台 App：非激活面板没有可调用的"交还 key"接口，
    /// 重新排一次窗口顺序会让窗口服务器把 key 交回前台 App 的窗口
    func relinquishKeyFocus() {
        guard isKeyWindow, isVisible else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    /// 用户手动切换（热键 / 菜单栏图标 / 点击面板外）
    func toggle() {
        if isPresented {
            hide()
        } else {
            show(auto: false)
        }
    }

    /// 显示面板（不抢键盘焦点）；auto 表示由新到的交互事件自动弹出
    func show(auto: Bool) {
        guard !isPresented else { return }
        isPresented = true
        isAutoPresented = auto
        if !isVisible {
            // 先同步完成一次布局，让面板以最新内容高度直接出现
            contentView?.layoutSubtreeIfNeeded()
            positionNearNotch()
            alphaValue = 0
        }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        isAutoPresented = false
        guard isPresented else { return }
        isPresented = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        } completionHandler: {
            // 淡出期间又被重新显示则不收起
            guard !self.isPresented else { return }
            self.orderOut(nil)
            self.alphaValue = 1
        }
    }
}
