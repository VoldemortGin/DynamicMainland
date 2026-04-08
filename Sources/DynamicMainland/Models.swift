import Foundation

// MARK: - Agent 类型

enum AgentKind: String, Codable, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case codex
    case geminiCli = "gemini_cli"
    case cursor
    case openCode = "open_code"
    case droid
    case qoder
    case copilot
    case codeBuddy = "code_buddy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCli: "Gemini CLI"
        case .cursor: "Cursor"
        case .openCode: "OpenCode"
        case .droid: "Droid"
        case .qoder: "Qoder"
        case .copilot: "Copilot"
        case .codeBuddy: "CodeBuddy"
        }
    }

    var iconName: String {
        switch self {
        case .claudeCode: "brain.head.profile"
        case .codex: "terminal"
        case .geminiCli: "sparkles"
        case .cursor: "cursorarrow.rays"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        case .droid: "cpu"
        case .qoder: "qrcode"
        case .copilot: "airplane"
        case .codeBuddy: "person.2"
        }
    }

    var accentColor: String {
        switch self {
        case .claudeCode: "#E8825A"
        case .codex: "#10A37F"
        case .geminiCli: "#4285F4"
        case .cursor: "#7B61FF"
        case .openCode: "#FF6B6B"
        case .droid: "#00D9FF"
        case .qoder: "#FFB800"
        case .copilot: "#1F6FEB"
        case .codeBuddy: "#22C55E"
        }
    }
}

// MARK: - 会话状态

enum SessionStatus: String, Codable {
    case active
    case waitingPermission = "waiting_permission"
    case waitingAnswer = "waiting_answer"
    case waitingPlanReview = "waiting_plan_review"
    case idle
    case completed
}

// MARK: - 工具操作

enum ToolAction: Codable {
    case readFile(path: String)
    case writeFile(path: String)
    case editFile(path: String)
    case executeBash(command: String)
    case webFetch(url: String)
    case search(query: String)
    case other(toolName: String, summary: String)

    var description: String {
        switch self {
        case .readFile(let path): "读取 \(shortenPath(path))"
        case .writeFile(let path): "写入 \(shortenPath(path))"
        case .editFile(let path): "编辑 \(shortenPath(path))"
        case .executeBash(let cmd): "执行 \(String(cmd.prefix(60)))"
        case .webFetch(let url): "获取 \(url)"
        case .search(let q): "搜索 \(q)"
        case .other(let name, _): name
        }
    }

    var iconName: String {
        switch self {
        case .readFile: "doc.text"
        case .writeFile: "doc.badge.plus"
        case .editFile: "pencil.line"
        case .executeBash: "terminal"
        case .webFetch: "globe"
        case .search: "magnifyingglass"
        case .other: "gearshape"
        }
    }

    // Codable 实现
    enum CodingKeys: String, CodingKey {
        case readFile = "read_file"
        case writeFile = "write_file"
        case editFile = "edit_file"
        case executeBash = "execute_bash"
        case webFetch = "web_fetch"
        case search
        case other
        case path, command, url, query, toolName = "tool_name", summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: serde_json_Value].self)

        if let path = dict["path"]?.stringValue {
            if dict["read_file"] != nil { self = .readFile(path: path); return }
            if dict["write_file"] != nil { self = .writeFile(path: path); return }
            if dict["edit_file"] != nil { self = .editFile(path: path); return }
        }
        if let cmd = dict["command"]?.stringValue {
            self = .executeBash(command: cmd); return
        }
        if let url = dict["url"]?.stringValue {
            self = .webFetch(url: url); return
        }
        if let q = dict["query"]?.stringValue {
            self = .search(query: q); return
        }

        self = .other(
            toolName: dict["tool_name"]?.stringValue ?? "unknown",
            summary: dict["summary"]?.stringValue ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        // 编码不需要，仅用于解码
    }
}

// 简单的 JSON 值包装
private enum serde_json_Value: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - 会话

struct AgentSession: Codable, Identifiable {
    let id: String
    let agent: AgentKind
    let terminalId: String
    let terminalApp: String
    let workingDir: String
    var status: SessionStatus
    var currentAction: ToolAction?
    var startedAtSecs: UInt64
    var lastActivitySecs: UInt64

    enum CodingKeys: String, CodingKey {
        case id, agent, status
        case terminalId = "terminal_id"
        case terminalApp = "terminal_app"
        case workingDir = "working_dir"
        case currentAction = "current_action"
        case startedAtSecs = "started_at_secs"
        case lastActivitySecs = "last_activity_secs"
    }

    var elapsedTime: String {
        let now = UInt64(Date().timeIntervalSince1970)
        let elapsed = now - startedAtSecs
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var shortWorkingDir: String {
        shortenPath(workingDir)
    }
}

// MARK: - 待处理事件

enum PendingEvent: Codable, Identifiable {
    case permissionRequest(
        sessionId: String, requestId: String, agent: AgentKind,
        toolName: String, description: String
    )
    case question(
        sessionId: String, requestId: String, agent: AgentKind,
        question: String, options: [String]
    )
    case notification(
        sessionId: String, agent: AgentKind, level: String, message: String
    )

    var id: String {
        switch self {
        case .permissionRequest(_, let rid, _, _, _): rid
        case .question(_, let rid, _, _, _): rid
        case .notification(let sid, _, _, let msg): "\(sid)-\(msg.hashValue)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type_ = "type"
        case sessionId = "session_id"
        case requestId = "request_id"
        case agent, toolName = "tool_name", description
        case question, options
        case level, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type_)

        switch type_ {
        case "permission_request":
            self = .permissionRequest(
                sessionId: try container.decode(String.self, forKey: .sessionId),
                requestId: try container.decode(String.self, forKey: .requestId),
                agent: try container.decode(AgentKind.self, forKey: .agent),
                toolName: try container.decode(String.self, forKey: .toolName),
                description: try container.decode(String.self, forKey: .description)
            )
        case "question":
            self = .question(
                sessionId: try container.decode(String.self, forKey: .sessionId),
                requestId: try container.decode(String.self, forKey: .requestId),
                agent: try container.decode(AgentKind.self, forKey: .agent),
                question: try container.decode(String.self, forKey: .question),
                options: try container.decodeIfPresent([String].self, forKey: .options) ?? []
            )
        case "notification":
            self = .notification(
                sessionId: try container.decode(String.self, forKey: .sessionId),
                agent: try container.decode(AgentKind.self, forKey: .agent),
                level: try container.decode(String.self, forKey: .level),
                message: try container.decode(String.self, forKey: .message)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "未知事件类型: \(type_)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {}
}

// MARK: - 工具函数

private func shortenPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    // 只保留最后两级路径
    let components = path.split(separator: "/")
    if components.count > 2 {
        return ".../" + components.suffix(2).joined(separator: "/")
    }
    return path
}
