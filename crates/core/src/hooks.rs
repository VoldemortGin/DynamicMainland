use crate::agent::AgentKind;

/// 为指定 Agent 安装 hook 配置
pub fn install_hook(agent: AgentKind, hook_client_path: &str, socket_path: &str) -> Result<(), String> {
    match agent {
        AgentKind::ClaudeCode => install_claude_code_hooks(hook_client_path, socket_path),
        // 其他 Agent 后续支持
        _ => Err(format!("{} 暂不支持自动 hook 安装", agent.display_name())),
    }
}

/// 检查指定 Agent 的 hook 是否已安装
pub fn is_hook_installed(agent: AgentKind) -> bool {
    match agent {
        AgentKind::ClaudeCode => check_claude_code_hooks(),
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

fn install_claude_code_hooks(hook_client_path: &str, socket_path: &str) -> Result<(), String> {
    let config_path = AgentKind::ClaudeCode
        .config_path()
        .ok_or("无法获取 Claude Code 配置路径")?;

    // 确保目录存在
    if let Some(parent) = config_path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("创建目录失败: {}", e))?;
    }

    // 读取现有配置
    let mut config: serde_json::Value = if config_path.exists() {
        let content =
            std::fs::read_to_string(&config_path).map_err(|e| format!("读取配置失败: {}", e))?;
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
    std::fs::write(&config_path, json_str).map_err(|e| format!("写入配置失败: {}", e))?;

    Ok(())
}

fn check_claude_code_hooks() -> bool {
    let config_path = match AgentKind::ClaudeCode.config_path() {
        Some(p) => p,
        None => return false,
    };

    if !config_path.exists() {
        return false;
    }

    let content = match std::fs::read_to_string(&config_path) {
        Ok(c) => c,
        Err(_) => return false,
    };

    // 检查是否包含 dm-hook 命令
    content.contains("dm-hook")
}
