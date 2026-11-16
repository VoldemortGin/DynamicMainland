use crate::agent::AgentKind;
use std::path::Path;

/// 为指定 Agent 安装 hook 配置
pub fn install_hook(agent: AgentKind, hook_client_path: &str, socket_path: &str) -> Result<(), String> {
    match agent {
        AgentKind::ClaudeCode => {
            let config_path = agent.config_path().ok_or("无法获取 Claude Code 配置路径")?;
            install_claude_code_hooks(&config_path, hook_client_path, socket_path)
        }
        // 其他 Agent 后续支持
        _ => Err(format!("{} 暂不支持自动 hook 安装", agent.display_name())),
    }
}

/// 检查指定 Agent 的 hook 是否已安装
pub fn is_hook_installed(agent: AgentKind) -> bool {
    match agent {
        AgentKind::ClaudeCode => agent
            .config_path()
            .is_some_and(|p| check_claude_code_hooks(&p)),
        _ => false,
    }
}

/// 为所有支持的 Agent 安装 hook
pub fn install_all_hooks(hook_client_path: &str, socket_path: &str) -> Vec<(AgentKind, Result<(), String>)> {
    let mut results = Vec::new();
    for &agent in AgentKind::all() {
        if agent.config_path().is_some() {
            let result = install_hook(agent, hook_client_path, socket_path);
            results.push((agent, result));
        }
    }
    results
}

/// 汇总安装结果：目前只有 Claude Code 支持自动安装，以它的结果作为整体结果
pub fn overall_install_result(results: &[(AgentKind, Result<(), String>)]) -> Result<(), String> {
    results
        .iter()
        .find(|(agent, _)| *agent == AgentKind::ClaudeCode)
        .map(|(_, result)| result.clone())
        .unwrap_or_else(|| Err("无法获取 Claude Code 配置路径".to_string()))
}

fn install_claude_code_hooks(
    config_path: &Path,
    hook_client_path: &str,
    socket_path: &str,
) -> Result<(), String> {
    // 确保目录存在
    if let Some(parent) = config_path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("创建目录失败: {}", e))?;
    }

    // 读取现有配置
    let mut config: serde_json::Value = if config_path.exists() {
        let content =
            std::fs::read_to_string(config_path).map_err(|e| format!("读取配置失败: {}", e))?;
        serde_json::from_str(&content).map_err(|e| format!("解析配置失败: {}", e))?
    } else {
        serde_json::json!({})
    };

    let hook_cmd = format!("{} --socket {} pre-tool-use", hook_client_path, socket_path);
    let post_hook_cmd = format!("{} --socket {} post-tool-use", hook_client_path, socket_path);
    let notify_cmd = format!("{} --socket {} notification", hook_client_path, socket_path);

    // 构建 hooks 配置
    let hooks = serde_json::json!({
        "PreToolUse": [
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": hook_cmd
                    }
                ]
            }
        ],
        "PostToolUse": [
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": post_hook_cmd
                    }
                ]
            }
        ],
        "Notification": [
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": notify_cmd
                    }
                ]
            }
        ]
    });

    config["hooks"] = hooks;

    let json_str =
        serde_json::to_string_pretty(&config).map_err(|e| format!("序列化失败: {}", e))?;
    std::fs::write(config_path, json_str).map_err(|e| format!("写入配置失败: {}", e))?;

    Ok(())
}

fn check_claude_code_hooks(config_path: &Path) -> bool {
    if !config_path.exists() {
        return false;
    }

    let content = match std::fs::read_to_string(config_path) {
        Ok(c) => c,
        Err(_) => return false,
    };

    // 检查是否包含 dm-hook 命令
    content.contains("dm-hook")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    /// 每个测试独占的临时配置目录，绝不触碰真实 home
    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "dm-hooks-test-{}-{}",
            std::process::id(),
            name
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn install_writes_hooks_and_keeps_existing_keys() {
        let dir = temp_dir("ok");
        let config_path = dir.join(".claude").join("settings.json");
        std::fs::create_dir_all(config_path.parent().unwrap()).unwrap();
        std::fs::write(&config_path, r#"{"model": "opus"}"#).unwrap();

        let result = install_claude_code_hooks(&config_path, "/opt/dm-hook", "/tmp/dm.sock");
        let results = vec![
            (AgentKind::ClaudeCode, result),
            (AgentKind::Codex, Err("Codex 暂不支持自动 hook 安装".to_string())),
        ];
        assert_eq!(overall_install_result(&results), Ok(()));

        let config: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&config_path).unwrap()).unwrap();
        assert_eq!(config["model"], "opus");
        assert_eq!(
            config["hooks"]["PreToolUse"][0]["hooks"][0]["command"],
            "/opt/dm-hook --socket /tmp/dm.sock pre-tool-use"
        );
        assert!(check_claude_code_hooks(&config_path));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn install_creates_missing_config_dir() {
        let dir = temp_dir("fresh");
        let config_path = dir.join(".claude").join("settings.json");
        assert!(!check_claude_code_hooks(&config_path));
        assert_eq!(
            install_claude_code_hooks(&config_path, "dm-hook", "/tmp/dm.sock"),
            Ok(())
        );
        assert!(check_claude_code_hooks(&config_path));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn install_fails_on_invalid_config_without_overwriting() {
        let dir = temp_dir("bad-json");
        let config_path = dir.join("settings.json");
        std::fs::write(&config_path, "{ not json").unwrap();

        let result = install_claude_code_hooks(&config_path, "dm-hook", "/tmp/dm.sock");
        let err = overall_install_result(&[(AgentKind::ClaudeCode, result)]).unwrap_err();
        assert!(err.starts_with("解析配置失败"), "{err}");
        assert_eq!(std::fs::read_to_string(&config_path).unwrap(), "{ not json");
        assert!(!check_claude_code_hooks(&config_path));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn install_fails_when_config_dir_is_a_file() {
        let dir = temp_dir("blocked");
        let blocker = dir.join(".claude");
        std::fs::write(&blocker, "").unwrap();

        let result =
            install_claude_code_hooks(&blocker.join("settings.json"), "dm-hook", "/tmp/dm.sock");
        assert!(result.unwrap_err().starts_with("创建目录失败"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn overall_result_fails_without_claude_code() {
        let results = vec![(AgentKind::Codex, Ok(()))];
        assert!(overall_install_result(&results).is_err());
    }
}
