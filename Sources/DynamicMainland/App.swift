import AppKit
import SwiftUI

/// DynamicMainland — AI Agent 刘海控制面板
/// 菜单栏应用，面板显示在刘海/屏幕顶部
@main
struct DynamicMainlandApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NotchPanel!
    private let viewModel = AgentViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupPanel()
        setupKeyboardShortcuts()

        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: "globe.asia.australia.fill",
            accessibilityDescription: "DynamicMainland"
        )
        button.image?.size = NSSize(width: 16, height: 16)
        button.action = #selector(statusBarClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            panel.toggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "安装 Hooks", action: #selector(installHooksAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 DynamicMainland", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func installHooksAction() {
        viewModel.installHooks()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 面板

    private func setupPanel() {
        let contentView = ContentView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)
        panel = NotchPanel(contentView: hostingView)
    }

    // MARK: - 键盘快捷键

    private func setupKeyboardShortcuts() {
        // Option + D: 切换面板
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKey(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleLocalKey(event) == true { return nil }
            return event
        }

        // 点击面板外关闭
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            if !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.panel.toggle()
            }
        }
    }

    private func handleGlobalKey(_ event: NSEvent) {
        // Option + D
        if event.modifierFlags.contains(.option) && event.keyCode == 2 {
            panel.toggle()
        }
    }

    private func handleLocalKey(_ event: NSEvent) -> Bool {
        // Option + D
        if event.modifierFlags.contains(.option) && event.keyCode == 2 {
            panel.toggle()
            return true
        }

        // ⌘Y: 批准当前权限请求
        if event.modifierFlags.contains(.command) && event.keyCode == 16 {
            if let first = viewModel.pendingEvents.first,
               case .permissionRequest(let sid, let rid, _, _, _) = first {
                viewModel.approvePermission(sessionId: sid, requestId: rid)
                return true
            }
        }

        // ⌘N: 拒绝当前权限请求
        if event.modifierFlags.contains(.command) && event.keyCode == 45 {
            if let first = viewModel.pendingEvents.first,
               case .permissionRequest(let sid, let rid, _, _, _) = first {
                viewModel.denyPermission(sessionId: sid, requestId: rid)
                return true
            }
        }

        // ⌘1-9: 快速选择问题选项
        if event.modifierFlags.contains(.command),
           let char = event.characters, let digit = char.first?.wholeNumberValue,
           digit >= 1 && digit <= 9 {
            if let first = viewModel.pendingEvents.first,
               case .question(let sid, let rid, _, _, let options) = first,
               digit <= options.count {
                viewModel.answerQuestion(
                    sessionId: sid, requestId: rid, answer: options[digit - 1]
                )
                return true
            }
        }

        return false
    }
}
