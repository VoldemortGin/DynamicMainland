use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// 支持的 AI 编码代理
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentKind {
    ClaudeCode,
    Codex,
    GeminiCli,
    Cursor,
    OpenCode,
    Droid,
    Qoder,
    Copilot,
    CodeBuddy,
}

impl AgentKind {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::ClaudeCode => "Claude Code",
            Self::Codex => "Codex",
            Self::GeminiCli => "Gemini CLI",
            Self::Cursor => "Cursor",
            Self::OpenCode => "OpenCode",
            Self::Droid => "Droid",
            Self::Qoder => "Qoder",
            Self::Copilot => "Copilot",
            Self::CodeBuddy => "CodeBuddy",
        }
    }

    /// 该 Agent 的 hook 配置文件路径
    pub fn config_path(&self) -> Option<PathBuf> {
        let home = dirs::home_dir()?;
        match self {
            Self::ClaudeCode => Some(home.join(".claude").join("settings.json")),
            Self::Codex => Some(home.join(".codex").join("config.json")),
            Self::GeminiCli => Some(home.join(".gemini").join("settings.json")),
            // 其他 Agent 后续支持
            _ => None,
        }
    }

    pub fn all() -> &'static [AgentKind] {
        &[
            Self::ClaudeCode,
            Self::Codex,
            Self::GeminiCli,
            Self::Cursor,
            Self::OpenCode,
            Self::Droid,
            Self::Qoder,
            Self::Copilot,
            Self::CodeBuddy,
        ]
    }
}
