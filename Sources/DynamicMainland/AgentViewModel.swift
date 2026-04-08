import Foundation
import SwiftUI
import Combine

/// 管理所有 Agent 会话状态的 ViewModel
@Observable
final class AgentViewModel {
    var sessions: [AgentSession] = []
    var pendingEvents: [PendingEvent] = []
    var hooksInstalled: Bool = false
    var isRunning: Bool = false

    private var pollTimer: Timer?
    private let bridge = RustBridge.shared

    func start() {
        bridge.start()
        isRunning = true
        hooksInstalled = bridge.hooksInstalled()

        // 每 200ms 轮询一次状态
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        bridge.stop()
        isRunning = false
    }

    func installHooks() {
        bridge.installHooks()
        hooksInstalled = bridge.hooksInstalled()
    }

    func approvePermission(sessionId: String, requestId: String) {
        bridge.respondPermission(sessionId: sessionId, requestId: requestId, approved: true)
        removePendingEvent(requestId: requestId)
    }

    func denyPermission(sessionId: String, requestId: String) {
        bridge.respondPermission(sessionId: sessionId, requestId: requestId, approved: false)
        removePendingEvent(requestId: requestId)
    }

    func answerQuestion(sessionId: String, requestId: String, answer: String) {
        bridge.respondQuestion(sessionId: sessionId, requestId: requestId, answer: answer)
        removePendingEvent(requestId: requestId)
    }

    func jumpToTerminal(sessionId: String) {
        bridge.jumpToTerminal(sessionId: sessionId)
    }

    // MARK: - Private

    private func poll() {
        sessions = bridge.getSessions()
        let newEvents = bridge.getPendingEvents()
        if !newEvents.isEmpty {
            // 合并新事件，避免重复
            let existingIds = Set(pendingEvents.map(\.id))
            for event in newEvents {
                if !existingIds.contains(event.id) {
                    pendingEvents.append(event)
                    // 播放通知音效
                    SoundManager.shared.playNotification(for: event)
                }
            }
        }
    }

    private func removePendingEvent(requestId: String) {
        pendingEvents.removeAll { $0.id == requestId }
    }
}
