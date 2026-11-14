use crate::agent::AgentKind;
use crate::session::*;
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;

/// Hook 客户端发来的事件
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum HookEvent {
    /// 会话开始/心跳
    #[serde(rename = "session_start")]
    SessionStart {
        session_id: String,
        agent: AgentKind,
        terminal_id: String,
        terminal_app: String,
        working_dir: String,
    },
    /// 工具使用前（需要权限审批）
    #[serde(rename = "pre_tool_use")]
    PreToolUse {
        session_id: String,
        request_id: String,
        tool_name: String,
        tool_input: serde_json::Value,
    },
    /// 工具使用后（通知）
    #[serde(rename = "post_tool_use")]
    PostToolUse {
        session_id: String,
        tool_name: String,
        tool_input: serde_json::Value,
    },
    /// Agent 提问
    #[serde(rename = "ask_question")]
    AskQuestion {
        session_id: String,
        request_id: String,
        question: String,
        options: Vec<String>,
    },
    /// 通知（完成、错误等）
    #[serde(rename = "notification")]
    Notification {
        session_id: String,
        level: String, // "info", "warning", "error", "success"
        message: String,
    },
    /// 会话结束
    #[serde(rename = "session_end")]
    SessionEnd { session_id: String },
    /// 停止指令（内部使用）
    #[serde(rename = "stop")]
    Stop,
}

/// 服务端响应
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum HookResponse {
    #[serde(rename = "ack")]
    Ack,
    #[serde(rename = "permission")]
    Permission { approved: bool },
    #[serde(rename = "answer")]
    Answer { text: String },
    #[serde(rename = "error")]
    Error { message: String },
}

/// 待处理的交互事件（传给 UI）
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum PendingEvent {
    #[serde(rename = "permission_request")]
    PermissionRequest {
        session_id: String,
        request_id: String,
        agent: AgentKind,
        tool_name: String,
        description: String,
    },
    #[serde(rename = "question")]
    Question {
        session_id: String,
        request_id: String,
        agent: AgentKind,
        question: String,
        options: Vec<String>,
    },
    #[serde(rename = "notification")]
    Notification {
        session_id: String,
        agent: AgentKind,
        level: String,
        message: String,
    },
}

impl PendingEvent {
    fn request_id(&self) -> Option<&str> {
        match self {
            PendingEvent::PermissionRequest { request_id, .. }
            | PendingEvent::Question { request_id, .. } => Some(request_id),
            PendingEvent::Notification { .. } => None,
        }
    }
}

/// 待处理事件及其入队时间（内部记录，不参与序列化）
struct PendingEntry {
    created_at_secs: u64,
    event: PendingEvent,
}

/// notification 类事件的最长存活时间（无 waiter，靠 TTL 和会话清理了结）
const NOTIFICATION_TTL_SECS: u64 = 300;

pub struct Server {
    session_mgr: SessionManager,
    pending_events: Arc<std::sync::Mutex<Vec<PendingEntry>>>,
    /// 等待 UI 响应的权限请求: request_id -> Sender<bool>
    permission_waiters: Arc<std::sync::Mutex<std::collections::HashMap<String, mpsc::Sender<bool>>>>,
    /// 等待 UI 响应的问题: request_id -> Sender<String>
    question_waiters: Arc<std::sync::Mutex<std::collections::HashMap<String, mpsc::Sender<String>>>>,
    running: Arc<AtomicBool>,
    socket_path: String,
}

impl Server {
    pub fn new(session_mgr: SessionManager) -> Self {
        let socket_path = Self::default_socket_path();
        Self {
            session_mgr,
            pending_events: Arc::new(std::sync::Mutex::new(Vec::new())),
            permission_waiters: Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
            question_waiters: Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
            running: Arc::new(AtomicBool::new(false)),
            socket_path,
        }
    }

    pub fn default_socket_path() -> String {
        let tmpdir = std::env::temp_dir();
        tmpdir
            .join("dynamic-mainland.sock")
            .to_string_lossy()
            .to_string()
    }

    pub fn socket_path(&self) -> &str {
        &self.socket_path
    }

    pub fn get_pending_events_json(&self) -> String {
        let events = self.pending_events.lock().unwrap();
        let list: Vec<&PendingEvent> = events.iter().map(|e| &e.event).collect();
        serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string())
    }

    pub fn drain_pending_events(&self) -> Vec<PendingEvent> {
        let mut events = self.pending_events.lock().unwrap();
        events.drain(..).map(|e| e.event).collect()
    }

    pub fn respond_permission(&self, request_id: &str, approved: bool) {
        if let Some(tx) = self.permission_waiters.lock().unwrap().remove(request_id) {
            let _ = tx.send(approved);
        }
        remove_pending_by_request_id(&self.pending_events, request_id);
    }

    pub fn respond_question(&self, request_id: &str, answer: &str) {
        if let Some(tx) = self.question_waiters.lock().unwrap().remove(request_id) {
            let _ = tx.send(answer.to_string());
        }
        remove_pending_by_request_id(&self.pending_events, request_id);
    }

    /// 清理已了结 / 过期的待处理事件：
    /// - 权限请求 / 问题：waiter 已不存在（已响应或已超时）即移除
    /// - notification：所属会话已清理或超过 TTL 即移除
    fn prune_pending_events(&self) {
        let live_sessions: std::collections::HashSet<String> =
            self.session_mgr.session_ids().into_iter().collect();
        let now = now_secs();
        // 先锁 pending 再锁 waiters；其余代码从不同时持有两把锁，不会死锁
        let mut events = self.pending_events.lock().unwrap();
        let perm_waiters = self.permission_waiters.lock().unwrap();
        let q_waiters = self.question_waiters.lock().unwrap();
        events.retain(|entry| match &entry.event {
            PendingEvent::PermissionRequest { request_id, .. } => {
                perm_waiters.contains_key(request_id)
            }
            PendingEvent::Question { request_id, .. } => q_waiters.contains_key(request_id),
            PendingEvent::Notification { session_id, .. } => {
                live_sessions.contains(session_id)
                    && now.saturating_sub(entry.created_at_secs) < NOTIFICATION_TTL_SECS
            }
        });
    }

    /// 启动 socket 服务器（阻塞当前线程）
    pub fn start(&self) {
        // 清理旧 socket 文件
        let _ = std::fs::remove_file(&self.socket_path);

        let listener = match UnixListener::bind(&self.socket_path) {
            Ok(l) => l,
            Err(e) => {
                eprintln!("[DM] 无法绑定 socket {}: {}", self.socket_path, e);
                return;
            }
        };

        // 设置 socket 权限为仅当前用户可访问
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(
                &self.socket_path,
                std::fs::Permissions::from_mode(0o700),
            );
        }

        self.running.store(true, Ordering::SeqCst);
        // 设置非阻塞以便能检查 running 标志
        listener.set_nonblocking(true).ok();

        eprintln!("[DM] 服务器启动: {}", self.socket_path);

        while self.running.load(Ordering::SeqCst) {
            match listener.accept() {
                Ok((stream, _)) => {
                    let session_mgr = self.session_mgr.clone();
                    let pending = self.pending_events.clone();
                    let perm_waiters = self.permission_waiters.clone();
                    let q_waiters = self.question_waiters.clone();
                    thread::spawn(move || {
                        handle_connection(stream, session_mgr, pending, perm_waiters, q_waiters);
                    });
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    // 没有新连接，短暂休眠
                    thread::sleep(std::time::Duration::from_millis(50));
                }
                Err(e) => {
                    eprintln!("[DM] accept 错误: {}", e);
                    thread::sleep(std::time::Duration::from_millis(100));
                }
            }

            // 定期清理超时会话（5 分钟无活动）及已了结的待处理事件
            self.session_mgr.cleanup_stale(300);
            self.prune_pending_events();
        }

        let _ = std::fs::remove_file(&self.socket_path);
        eprintln!("[DM] 服务器已停止");
    }

    pub fn stop(&self) {
        self.running.store(false, Ordering::SeqCst);
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }
}

fn handle_connection(
    stream: UnixStream,
    session_mgr: SessionManager,
    pending_events: Arc<std::sync::Mutex<Vec<PendingEntry>>>,
    permission_waiters: Arc<std::sync::Mutex<std::collections::HashMap<String, mpsc::Sender<bool>>>>,
    question_waiters: Arc<std::sync::Mutex<std::collections::HashMap<String, mpsc::Sender<String>>>>,
) {
    stream.set_nonblocking(false).ok();
    // 读取超时 30 秒（对于权限请求可能需要等待用户响应）
    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(120)))
        .ok();

    let reader = BufReader::new(&stream);
    let mut writer = &stream;

    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };

        if line.trim().is_empty() {
            continue;
        }

        let event: HookEvent = match serde_json::from_str(&line) {
            Ok(e) => e,
            Err(e) => {
                let resp = HookResponse::Error {
                    message: format!("JSON 解析错误: {}", e),
                };
                let _ = writeln!(writer, "{}", serde_json::to_string(&resp).unwrap());
                continue;
            }
        };

        let response = process_event(
            event,
            &session_mgr,
            &pending_events,
            &permission_waiters,
            &question_waiters,
        );

        let resp_json = serde_json::to_string(&response).unwrap();
        if writeln!(writer, "{}", resp_json).is_err() {
            break;
        }
    }
}

fn remove_pending_by_request_id(
    pending_events: &std::sync::Mutex<Vec<PendingEntry>>,
    request_id: &str,
) {
    let mut events = pending_events.lock().unwrap();
    events.retain(|e| e.event.request_id() != Some(request_id));
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn process_event(
    event: HookEvent,
    session_mgr: &SessionManager,
    pending_events: &Arc<std::sync::Mutex<Vec<PendingEntry>>>,
    permission_waiters: &Arc<std::sync::Mutex<std::collections::HashMap<String, mpsc::Sender<bool>>>>,
    question_waiters: &Arc<std::sync::Mutex<std::collections::HashMap<String, mpsc::Sender<String>>>>,
) -> HookResponse {
    match event {
        HookEvent::SessionStart {
            session_id,
            agent,
            terminal_id,
            terminal_app,
            working_dir,
        } => {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            session_mgr.upsert_session(Session {
                id: session_id,
                agent,
                terminal_id,
                terminal_app,
                working_dir,
                status: SessionStatus::Active,
                current_action: None,
                pending_permission: None,
                pending_question: None,
                pending_plan: None,
                started_at_secs: now,
                last_activity_secs: now,
            });
            HookResponse::Ack
        }

        HookEvent::PreToolUse {
            session_id,
            request_id,
            tool_name,
            tool_input,
        } => {
            let description = summarize_tool(&tool_name, &tool_input);
            let action = parse_tool_action(&tool_name, &tool_input);

            // 更新会话当前操作
            session_mgr.update_action(&session_id, Some(action));

            // 获取 agent 类型
            let agent = session_mgr
                .get_session(&session_id)
                .map(|s| s.agent)
                .unwrap_or(AgentKind::ClaudeCode);

            // 创建响应通道
            let (tx, rx) = mpsc::channel();
            permission_waiters
                .lock()
                .unwrap()
                .insert(request_id.clone(), tx);

            // 推送待处理事件给 UI
            pending_events.lock().unwrap().push(PendingEntry {
                created_at_secs: now_secs(),
                event: PendingEvent::PermissionRequest {
                    session_id: session_id.clone(),
                    request_id: request_id.clone(),
                    agent,
                    tool_name,
                    description,
                },
            });

            session_mgr.update_status(&session_id, SessionStatus::WaitingPermission);

            // 等待 UI 响应（最多 120 秒）
            match rx.recv_timeout(std::time::Duration::from_secs(120)) {
                Ok(approved) => {
                    session_mgr.clear_pending(&session_id);
                    HookResponse::Permission { approved }
                }
                Err(_) => {
                    // 超时，默认拒绝
                    permission_waiters.lock().unwrap().remove(&request_id);
                    remove_pending_by_request_id(pending_events, &request_id);
                    session_mgr.clear_pending(&session_id);
                    HookResponse::Permission { approved: false }
                }
            }
        }

        HookEvent::PostToolUse {
            session_id,
            tool_name,
            tool_input,
        } => {
            let action = parse_tool_action(&tool_name, &tool_input);
            session_mgr.update_action(&session_id, Some(action));
            session_mgr.update_status(&session_id, SessionStatus::Active);
            HookResponse::Ack
        }

        HookEvent::AskQuestion {
            session_id,
            request_id,
            question,
            options,
        } => {
            let agent = session_mgr
                .get_session(&session_id)
                .map(|s| s.agent)
                .unwrap_or(AgentKind::ClaudeCode);

            let (tx, rx) = mpsc::channel();
            question_waiters
                .lock()
                .unwrap()
                .insert(request_id.clone(), tx);

            pending_events.lock().unwrap().push(PendingEntry {
                created_at_secs: now_secs(),
                event: PendingEvent::Question {
                    session_id: session_id.clone(),
                    request_id: request_id.clone(),
                    agent,
                    question,
                    options,
                },
            });

            session_mgr.update_status(&session_id, SessionStatus::WaitingAnswer);

            match rx.recv_timeout(std::time::Duration::from_secs(120)) {
                Ok(text) => {
                    session_mgr.clear_pending(&session_id);
                    HookResponse::Answer { text }
                }
                Err(_) => {
                    question_waiters.lock().unwrap().remove(&request_id);
                    remove_pending_by_request_id(pending_events, &request_id);
                    session_mgr.clear_pending(&session_id);
                    HookResponse::Error {
                        message: "响应超时".to_string(),
                    }
                }
            }
        }

        HookEvent::Notification {
            session_id,
            level,
            message,
        } => {
            let agent = session_mgr
                .get_session(&session_id)
                .map(|s| s.agent)
                .unwrap_or(AgentKind::ClaudeCode);

            pending_events.lock().unwrap().push(PendingEntry {
                created_at_secs: now_secs(),
                event: PendingEvent::Notification {
                    session_id,
                    agent,
                    level,
                    message,
                },
            });
            HookResponse::Ack
        }

        HookEvent::SessionEnd { session_id } => {
            session_mgr.update_status(&session_id, SessionStatus::Completed);
            // 延迟几秒后移除，让 UI 有时间显示完成状态
            let mgr = session_mgr.clone();
            let sid = session_id.clone();
            thread::spawn(move || {
                thread::sleep(std::time::Duration::from_secs(5));
                mgr.remove_session(&sid);
            });
            HookResponse::Ack
        }

        HookEvent::Stop => HookResponse::Ack,
    }
}

fn summarize_tool(tool_name: &str, input: &serde_json::Value) -> String {
    match tool_name {
        "Read" => {
            let path = input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            format!("读取文件: {}", path)
        }
        "Write" => {
            let path = input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            format!("写入文件: {}", path)
        }
        "Edit" => {
            let path = input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            format!("编辑文件: {}", path)
        }
        "Bash" => {
            let cmd = input
                .get("command")
                .and_then(|v| v.as_str())
                .unwrap_or("...");
            let truncated: String = cmd.chars().take(80).collect();
            format!("执行命令: {}", truncated)
        }
        "WebFetch" => {
            let url = input
                .get("url")
                .and_then(|v| v.as_str())
                .unwrap_or("...");
            format!("获取网页: {}", url)
        }
        _ => format!("工具: {}", tool_name),
    }
}

fn parse_tool_action(tool_name: &str, input: &serde_json::Value) -> ToolAction {
    match tool_name {
        "Read" => ToolAction::ReadFile {
            path: input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        },
        "Write" => ToolAction::WriteFile {
            path: input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        },
        "Edit" => ToolAction::EditFile {
            path: input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        },
        "Bash" => ToolAction::ExecuteBash {
            command: input
                .get("command")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        },
        "WebFetch" => ToolAction::WebFetch {
            url: input
                .get("url")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        },
        "Grep" | "Glob" => ToolAction::Search {
            query: input
                .get("pattern")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        },
        _ => ToolAction::Other {
            tool_name: tool_name.to_string(),
            summary: serde_json::to_string(input)
                .unwrap_or_default()
                .chars()
                .take(100)
                .collect(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    fn make_session(id: &str) -> Session {
        let now = now_secs();
        Session {
            id: id.to_string(),
            agent: AgentKind::ClaudeCode,
            terminal_id: "t1".to_string(),
            terminal_app: "Terminal".to_string(),
            working_dir: "/tmp".to_string(),
            status: SessionStatus::Active,
            current_action: None,
            pending_permission: None,
            pending_question: None,
            pending_plan: None,
            started_at_secs: now,
            last_activity_secs: now,
        }
    }

    fn push_entry(server: &Server, created_at_secs: u64, event: PendingEvent) {
        server.pending_events.lock().unwrap().push(PendingEntry {
            created_at_secs,
            event,
        });
    }

    fn pending_count(server: &Server) -> usize {
        server.pending_events.lock().unwrap().len()
    }

    #[test]
    fn respond_permission_settles_event_and_wakes_waiter() {
        let mgr = SessionManager::new();
        let server = Server::new(mgr.clone());
        mgr.upsert_session(make_session("s1"));

        let pending = server.pending_events.clone();
        let perm_waiters = server.permission_waiters.clone();
        let q_waiters = server.question_waiters.clone();
        let mgr2 = mgr.clone();
        let handle = std::thread::spawn(move || {
            process_event(
                HookEvent::PreToolUse {
                    session_id: "s1".to_string(),
                    request_id: "r1".to_string(),
                    tool_name: "Bash".to_string(),
                    tool_input: serde_json::json!({"command": "ls"}),
                },
                &mgr2,
                &pending,
                &perm_waiters,
                &q_waiters,
            )
        });

        // 等待事件进入 pending_events
        let deadline = Instant::now() + Duration::from_secs(5);
        while pending_count(&server) == 0 {
            assert!(Instant::now() < deadline, "权限事件未出现在 pending_events 中");
            std::thread::sleep(Duration::from_millis(5));
        }

        server.respond_permission("r1", true);
        match handle.join().unwrap() {
            HookResponse::Permission { approved } => assert!(approved),
            other => panic!("非预期响应: {:?}", other),
        }
        assert_eq!(pending_count(&server), 0, "响应后事件应从 pending_events 移除");
        assert!(server.permission_waiters.lock().unwrap().is_empty());
    }

    #[test]
    fn respond_without_waiter_is_noop() {
        // 模拟「点 Allow 恰好撞上超时」：waiter 已被超时路径移除
        let server = Server::new(SessionManager::new());
        server.respond_permission("ghost", true);
        server.respond_question("ghost", "answer");
        assert_eq!(pending_count(&server), 0);
    }

    #[test]
    fn prune_removes_settled_and_expired_events() {
        let mgr = SessionManager::new();
        let server = Server::new(mgr.clone());
        mgr.upsert_session(make_session("alive"));
        let now = now_secs();

        // 1. 存活会话的新 notification -> 保留
        push_entry(
            &server,
            now,
            PendingEvent::Notification {
                session_id: "alive".to_string(),
                agent: AgentKind::ClaudeCode,
                level: "info".to_string(),
                message: "fresh".to_string(),
            },
        );
        // 2. 超过 TTL 的 notification -> 移除
        push_entry(
            &server,
            now.saturating_sub(NOTIFICATION_TTL_SECS + 1),
            PendingEvent::Notification {
                session_id: "alive".to_string(),
                agent: AgentKind::ClaudeCode,
                level: "info".to_string(),
                message: "expired".to_string(),
            },
        );
        // 3. 会话已清理的 notification -> 移除
        push_entry(
            &server,
            now,
            PendingEvent::Notification {
                session_id: "dead".to_string(),
                agent: AgentKind::ClaudeCode,
                level: "info".to_string(),
                message: "orphan".to_string(),
            },
        );
        // 4. 无 waiter 的权限请求（已超时/已响应）-> 移除
        push_entry(
            &server,
            now,
            PendingEvent::PermissionRequest {
                session_id: "alive".to_string(),
                request_id: "r-done".to_string(),
                agent: AgentKind::ClaudeCode,
                tool_name: "Bash".to_string(),
                description: "settled".to_string(),
            },
        );
        // 5. 有 waiter 的权限请求 -> 保留
        let (tx, _rx) = mpsc::channel();
        server
            .permission_waiters
            .lock()
            .unwrap()
            .insert("r-waiting".to_string(), tx);
        push_entry(
            &server,
            now,
            PendingEvent::PermissionRequest {
                session_id: "alive".to_string(),
                request_id: "r-waiting".to_string(),
                agent: AgentKind::ClaudeCode,
                tool_name: "Bash".to_string(),
                description: "waiting".to_string(),
            },
        );

        server.prune_pending_events();

        let events = server.pending_events.lock().unwrap();
        assert_eq!(events.len(), 2);
        let has = |pred: &dyn Fn(&PendingEvent) -> bool| events.iter().any(|e| pred(&e.event));
        assert!(has(&|e| matches!(
            e,
            PendingEvent::Notification { message, .. } if message == "fresh"
        )));
        assert!(has(&|e| matches!(
            e,
            PendingEvent::PermissionRequest { request_id, .. } if request_id == "r-waiting"
        )));
    }

    #[test]
    fn remove_pending_by_request_id_only_removes_match() {
        let server = Server::new(SessionManager::new());
        let now = now_secs();
        push_entry(
            &server,
            now,
            PendingEvent::Question {
                session_id: "s1".to_string(),
                request_id: "q1".to_string(),
                agent: AgentKind::ClaudeCode,
                question: "?".to_string(),
                options: vec![],
            },
        );
        push_entry(
            &server,
            now,
            PendingEvent::Notification {
                session_id: "s1".to_string(),
                agent: AgentKind::ClaudeCode,
                level: "info".to_string(),
                message: "keep".to_string(),
            },
        );

        remove_pending_by_request_id(&server.pending_events, "q1");

        let events = server.pending_events.lock().unwrap();
        assert_eq!(events.len(), 1);
        assert!(matches!(
            &events[0].event,
            PendingEvent::Notification { message, .. } if message == "keep"
        ));
    }
}
