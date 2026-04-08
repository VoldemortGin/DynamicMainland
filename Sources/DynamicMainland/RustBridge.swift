import Foundation
import CDynamicMainland

/// Rust 核心引擎的 Swift 桥接层
final class RustBridge {
    static let shared = RustBridge()

    private init() {}

    /// 启动核心引擎
    func start() {
        dm_start()
    }

    /// 停止核心引擎
    func stop() {
        dm_stop()
    }

    /// 获取所有活跃会话
    func getSessions() -> [AgentSession] {
        guard let ptr = dm_get_sessions_json() else { return [] }
        defer { dm_free_string(ptr) }
        let json = String(cString: ptr)
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([AgentSession].self, from: data)) ?? []
    }

    /// 获取待处理事件
    func getPendingEvents() -> [PendingEvent] {
        guard let ptr = dm_get_pending_events_json() else { return [] }
        defer { dm_free_string(ptr) }
        let json = String(cString: ptr)
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PendingEvent].self, from: data)) ?? []
    }

    /// 响应权限请求
    func respondPermission(sessionId: String, requestId: String, approved: Bool) {
        sessionId.withCString { sid in
            requestId.withCString { rid in
                dm_respond_permission(sid, rid, approved)
            }
        }
    }

    /// 响应用户问题
    func respondQuestion(sessionId: String, requestId: String, answer: String) {
        sessionId.withCString { sid in
            requestId.withCString { rid in
                answer.withCString { ans in
                    dm_respond_question(sid, rid, ans)
                }
            }
        }
    }

    /// 安装 hooks
    func installHooks() {
        dm_install_hooks()
    }

    /// 检查 hooks 是否已安装
    func hooksInstalled() -> Bool {
        dm_hooks_installed()
    }

    /// 跳转到终端
    func jumpToTerminal(sessionId: String) {
        sessionId.withCString { sid in
            dm_jump_to_terminal(sid)
        }
    }

    /// 获取 socket 路径
    func getSocketPath() -> String {
        guard let ptr = dm_get_socket_path() else { return "" }
        defer { dm_free_string(ptr) }
        return String(cString: ptr)
    }
}
