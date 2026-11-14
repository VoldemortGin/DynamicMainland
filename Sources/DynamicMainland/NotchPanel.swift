import AppKit
import SwiftUI

/// 刘海区域的浮动面板 — 深色圆角，非激活式
final class NotchPanel: NSPanel {
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

    func positionNearNotch() {
        // 优先选带刘海的屏幕，没有则回退到主屏
        let notchScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notchScreen ?? NSScreen.main else { return }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let hasNotch = screen.safeAreaInsets.top > 0

        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 440

        let x = screenFrame.midX - panelWidth / 2
        let y: CGFloat
        if hasNotch {
            y = screenFrame.maxY - screen.safeAreaInsets.top - panelHeight - 4
        } else {
            y = visibleFrame.maxY - panelHeight - 4
        }

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    /// 文本输入结束后把键盘焦点还给前台 App：非激活面板没有可调用的"交还 key"接口，
    /// 重新排一次窗口顺序会让窗口服务器把 key 交回前台 App 的窗口
    func relinquishKeyFocus() {
        guard isKeyWindow, isVisible else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    func toggle() {
        if isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            } completionHandler: {
                self.orderOut(nil)
                self.alphaValue = 1
            }
        } else {
            positionNearNotch()
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1
            }
        }
    }
}
