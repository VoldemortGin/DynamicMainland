import AppKit
import SwiftUI

/// 刘海区域的浮动面板 — 深色半透明，非激活式
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

        // 深色圆角
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 14
        self.contentView?.layer?.masksToBounds = true
        self.contentView?.layer?.borderWidth = 1
        self.contentView?.layer?.borderColor = NSColor(white: 0.2, alpha: 0.5).cgColor

        positionNearNotch()
    }

    func positionNearNotch() {
        guard let screen = NSScreen.main else { return }

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

    func toggle() {
        if isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
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
                ctx.duration = 0.15
                self.animator().alphaValue = 1
            }
        }
    }
}
