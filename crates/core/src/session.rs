use crate::agent::AgentKind;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;

/// 会话状态
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Active,
    WaitingPermission,
    WaitingAnswer,
    WaitingPlanReview,
    Idle,
    Completed,
}

/// 工具操作类型
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolAction {
    ReadFile { path: String },
    WriteFile { path: String },
    EditFile { path: String },
    ExecuteBash { command: String },
    WebFetch { url: String },
    Search { query: String },
    Other { tool_name: String, summary: String },
}

/// 权限请求
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermissionRequest {
    pub request_id: String,
    pub tool_name: String,
    pub action: ToolAction,
    pub description: String,
    #[serde(skip)]
    pub response_tx: Option<std::sync::mpsc::Sender<bool>>,
}

/// 用户问题
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserQuestion {
    pub request_id: String,
    pub question: String,
    pub options: Vec<String>,
    #[serde(skip)]
    pub response_tx: Option<std::sync::mpsc::Sender<String>>,
}

/// 计划审查
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanReview {
    pub request_id: String,
    pub plan_markdown: String,
    #[serde(skip)]
    pub response_tx: Option<std::sync::mpsc::Sender<bool>>,
}

/// 一个 Agent 会话
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub agent: AgentKind,
    pub terminal_id: String,
    pub terminal_app: String,
    pub working_dir: String,
    pub status: SessionStatus,
    pub current_action: Option<ToolAction>,
    pub pending_permission: Option<PermissionRequest>,
    pub pending_question: Option<UserQuestion>,
    pub pending_plan: Option<PlanReview>,
    /// 会话开始时间（序列化为秒数）
    pub started_at_secs: u64,
    /// 最后活动时间
    pub last_activity_secs: u64,
}

/// 会话管理器
#[derive(Clone)]
pub struct SessionManager {
    sessions: Arc<Mutex<HashMap<String, Session>>>,
    start_times: Arc<Mutex<HashMap<String, Instant>>>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            start_times: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn upsert_session(&self, session: Session) {
        let id = session.id.clone();
        let mut sessions = self.sessions.lock().unwrap();
        let mut times = self.start_times.lock().unwrap();
        times.entry(id.clone()).or_insert_with(Instant::now);
        sessions.insert(id, session);
    }

    pub fn update_status(&self, session_id: &str, status: SessionStatus) {
        if let Some(session) = self.sessions.lock().unwrap().get_mut(session_id) {
            session.status = status;
            session.last_activity_secs = elapsed_secs();
        }
    }

    pub fn update_action(&self, session_id: &str, action: Option<ToolAction>) {
        if let Some(session) = self.sessions.lock().unwrap().get_mut(session_id) {
            session.current_action = action;
            session.last_activity_secs = elapsed_secs();
        }
    }

    pub fn set_pending_permission(&self, session_id: &str, perm: PermissionRequest) {
        if let Some(session) = self.sessions.lock().unwrap().get_mut(session_id) {
            session.status = SessionStatus::WaitingPermission;
            session.pending_permission = Some(perm);
            session.last_activity_secs = elapsed_secs();
        }
    }

    pub fn set_pending_question(&self, session_id: &str, question: UserQuestion) {
        if let Some(session) = self.sessions.lock().unwrap().get_mut(session_id) {
            session.status = SessionStatus::WaitingAnswer;
            session.pending_question = Some(question);
            session.last_activity_secs = elapsed_secs();
        }
    }

    pub fn set_pending_plan(&self, session_id: &str, plan: PlanReview) {
        if let Some(session) = self.sessions.lock().unwrap().get_mut(session_id) {
            session.status = SessionStatus::WaitingPlanReview;
            session.pending_plan = Some(plan);
            session.last_activity_secs = elapsed_secs();
        }
    }

    pub fn clear_pending(&self, session_id: &str) {
        if let Some(session) = self.sessions.lock().unwrap().get_mut(session_id) {
            session.pending_permission = None;
            session.pending_question = None;
            session.pending_plan = None;
            session.status = SessionStatus::Active;
            session.last_activity_secs = elapsed_secs();
        }
    }

    pub fn remove_session(&self, session_id: &str) {
        self.sessions.lock().unwrap().remove(session_id);
        self.start_times.lock().unwrap().remove(session_id);
    }

    /// 清理超时会话（超过 5 分钟无活动）
    pub fn cleanup_stale(&self, timeout_secs: u64) {
        let now = elapsed_secs();
        let mut sessions = self.sessions.lock().unwrap();
        sessions.retain(|_, s| now - s.last_activity_secs < timeout_secs);
    }

    pub fn get_all_sessions_json(&self) -> String {
        let sessions = self.sessions.lock().unwrap();
        let list: Vec<&Session> = sessions.values().collect();
        serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string())
    }

    pub fn get_session(&self, session_id: &str) -> Option<Session> {
        self.sessions.lock().unwrap().get(session_id).cloned()
    }

    pub fn session_count(&self) -> usize {
        self.sessions.lock().unwrap().len()
    }
}

fn elapsed_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}
