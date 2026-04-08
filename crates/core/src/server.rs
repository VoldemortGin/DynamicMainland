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

pub struct Server {
    session_mgr: SessionManager,
    pending_events: Arc<std::sync::Mutex<Vec<PendingEvent>>>,
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
        serde_json::to_string(&*events).unwrap_or_else(|_| "[]".to_string())
    }

    pub fn drain_pending_events(&self) -> Vec<PendingEvent> {
        let mut events = self.pending_events.lock().unwrap();
        std::mem::take(&mut *events)
    }

    pub fn respond_permission(&self, request_id: &str, approved: bool) {
        if let Some(tx) = self.permission_waiters.lock().unwrap().remove(request_id) {
            let _ = tx.send(approved);
        }
    }

    pub fn respond_question(&self, request_id: &str, answer: &str) {
        if let Some(tx) = self.question_waiters.lock().unwrap().remove(request_id) {
            let _ = tx.send(answer.to_string());
        }
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

            // 定期清理超时会话（5 分钟无活动）
            self.session_mgr.cleanup_stale(300);
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
    pending_events: Arc<std::sync::Mutex<Vec<PendingEvent>>>,
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

fn process_event(
    event: HookEvent,
    session_mgr: &SessionManager,
    pending_events: &Arc<std::sync::Mutex<Vec<PendingEvent>>>,
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
            pending_events
                .lock()
                .unwrap()
                .push(PendingEvent::PermissionRequest {
                    session_id: session_id.clone(),
                    request_id: request_id.clone(),
                    agent,
                    tool_name,
                    description,
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

            pending_events
                .lock()
                .unwrap()
                .push(PendingEvent::Question {
                    session_id: session_id.clone(),
                    request_id: request_id.clone(),
                    agent,
                    question,
                    options,
                });

            session_mgr.update_status(&session_id, SessionStatus::WaitingAnswer);

            match rx.recv_timeout(std::time::Duration::from_secs(120)) {
                Ok(text) => {
                    session_mgr.clear_pending(&session_id);
                    HookResponse::Answer { text }
                }
                Err(_) => {
                    question_waiters.lock().unwrap().remove(&request_id);
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

            pending_events
                .lock()
                .unwrap()
                .push(PendingEvent::Notification {
                    session_id,
                    agent,
                    level,
                    message,
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
