import Foundation
import SwiftUI
import Combine

/// 管理所有 Agent 会话状态的 ViewModel
@Observable
final class AgentViewModel {
    var sessions: [AgentSession] = []
    var pendingEvents: [PendingEvent] = [] {
        didSet {
            if pendingEvents.count != oldValue.count {
                onPendingCountChange?(pendingEvents.count)
            }
            if pendingEvents != oldValue {
                onPendingEventsChange?(pendingEvents)
            }
        }
    }
    var hooksInstalled: Bool = false
    /// 最近一次安装 hooks 的结果，几秒后自动清除
    var installFeedback: InstallFeedback?
    var isRunning: Bool = false
    /// 待处理事件数量变化回调（供菜单栏徽章使用）
    var onPendingCountChange: ((Int) -> Void)?
    /// 待处理事件列表变化回调（供全局热键按需注册/注销使用）
    var onPendingEventsChange: (([PendingEvent]) -> Void)?

    private var pollTimer: Timer?
    private let bridge = RustBridge.shared
    /// 本地已响应 / 已关闭的事件 id（Rust 侧移除有延迟，且 notification 的关闭只记录在本地）
    private var handledEventIds: Set<String> = []
    /// 已播放过音效的事件 id
    private var seenEventIds: Set<String> = []
    private var installFeedbackClear: DispatchWorkItem?

    func start() {
        bridge.start()
        isRunning = true
        hooksInstalled = bridge.hooksInstalled()

        // 每 200ms 轮询一次状态（.common 模式保证拖动面板/追踪菜单时不冻结）
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        bridge.stop()
        isRunning = false
    }

    func installHooks() {
        let error = bridge.installHooks()
        hooksInstalled = bridge.hooksInstalled()
        installFeedback = InstallFeedback(error: error)

        installFeedbackClear?.cancel()
        let clear = DispatchWorkItem { [weak self] in self?.installFeedback = nil }
        installFeedbackClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: clear)
    }

    /// ⌃⇧Y / ⌃⇧N 作用的目标：第一个待处理权限请求（跳过排在前面的通知 / 提问）
    var firstPermissionRequest: (sessionId: String, requestId: String)? {
        for case .permissionRequest(let sid, let rid, _, _, _, _) in pendingEvents {
            return (sid, rid)
        }
        return nil
    }

    func approvePermission(sessionId: String, requestId: String) {
        bridge.respondPermission(sessionId: sessionId, requestId: requestId, approved: true)
        markEventHandled(id: requestId)
    }

    /// 对当前所有待处理权限请求逐条允许（不影响提问和通知）
    func approveAllPermissions() {
        for case .permissionRequest(let sid, let rid, _, _, _, _) in pendingEvents {
            approvePermission(sessionId: sid, requestId: rid)
        }
    }

    func denyPermission(sessionId: String, requestId: String) {
        bridge.respondPermission(sessionId: sessionId, requestId: requestId, approved: false)
        markEventHandled(id: requestId)
    }

    func answerQuestion(sessionId: String, requestId: String, answer: String) {
        bridge.respondQuestion(sessionId: sessionId, requestId: requestId, answer: answer)
        markEventHandled(id: requestId)
    }

    func dismissNotification(id: String) {
        markEventHandled(id: id)
    }

    func jumpToTerminal(sessionId: String) {
        bridge.jumpToTerminal(sessionId: sessionId)
    }

    // MARK: - Private

    private func poll() {
        let newSessions = bridge.getSessions()
        if newSessions != sessions {
            sessions = newSessions
        }

        // 对账：以 Rust 快照为全集，用本地已处理集合过滤
        let snapshot = bridge.getPendingEvents()
        let snapshotIds = Set(snapshot.map(\.id))
        handledEventIds.formIntersection(snapshotIds)

        // 音效只在真正新出现的事件上播放一次
        for event in snapshot where !seenEventIds.contains(event.id) {
            SoundManager.shared.playNotification(for: event)
        }
        seenEventIds = snapshotIds

        var visibleIds = Set<String>()
        let visible = snapshot.filter { visibleIds.insert($0.id).inserted && !handledEventIds.contains($0.id) }
        if visible != pendingEvents {
            pendingEvents = visible
        }
    }

    private func markEventHandled(id: String) {
        handledEventIds.insert(id)
        pendingEvents.removeAll { $0.id == id }
    }
}

/// 安装 hooks 的结果反馈
struct InstallFeedback: Equatable {
    /// 失败原因；nil 表示成功
    let error: String?

    var message: String {
        error.map { "Install failed: \($0)" } ?? "Hooks installed for Claude Code"
    }
}
