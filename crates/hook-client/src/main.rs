use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::process::ExitCode;

/// Hook 客户端 — AI Agent 的 hook 脚本调用此程序与 DynamicMainland 核心通信
///
/// 用法:
///   dm-hook --socket <path> pre-tool-use    # 工具使用前（stdin 接收 JSON）
///   dm-hook --socket <path> post-tool-use   # 工具使用后（stdin 接收 JSON）
///   dm-hook --socket <path> notification    # 通知事件（stdin 接收 JSON）

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
enum HookEvent {
    #[serde(rename = "session_start")]
    SessionStart {
        session_id: String,
        agent: String,
        terminal_id: String,
        terminal_app: String,
        working_dir: String,
    },
    #[serde(rename = "pre_tool_use")]
    PreToolUse {
        session_id: String,
        request_id: String,
        tool_name: String,
        tool_input: serde_json::Value,
    },
    #[serde(rename = "post_tool_use")]
    PostToolUse {
        session_id: String,
        tool_name: String,
        tool_input: serde_json::Value,
    },
    #[serde(rename = "notification")]
    Notification {
        session_id: String,
        level: String,
        message: String,
    },
    #[serde(rename = "session_end")]
    SessionEnd {
        session_id: String,
    },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum HookResponse {
    #[serde(rename = "ack")]
    Ack,
    #[serde(rename = "permission")]
    Permission { approved: bool },
    #[serde(rename = "answer")]
    Answer { text: String },
    #[serde(rename = "error")]
    Error { message: String },
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();

    let socket_path = get_arg(&args, "--socket").unwrap_or_else(|| {
        std::env::temp_dir()
            .join("dynamic-mainland.sock")
            .to_string_lossy()
            .to_string()
    });

    let command = args.last().map(|s| s.as_str()).unwrap_or("unknown");

    // 从 stdin 读取 hook 数据
    let mut stdin_data = String::new();
    if let Err(_) = std::io::stdin().read_to_string(&mut stdin_data) {
        // stdin 可能为空
        stdin_data = "{}".to_string();
    }

    let hook_input: serde_json::Value =
        serde_json::from_str(&stdin_data).unwrap_or(serde_json::json!({}));

    // 生成会话 ID（基于 PID 和终端信息）
    let session_id = generate_session_id();
    let request_id = generate_request_id();

    // 检测终端
    let terminal_app = detect_terminal();
    let terminal_id = std::env::var("TERM_SESSION_ID").unwrap_or_else(|_| "default".to_string());
    let working_dir = std::env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();

    // 先发送 session_start 确保会话存在
    let start_event = HookEvent::SessionStart {
        session_id: session_id.clone(),
        agent: "claude_code".to_string(),
        terminal_id: terminal_id.clone(),
        terminal_app: terminal_app.clone(),
        working_dir: working_dir.clone(),
    };

    // 连接 socket
    let mut stream = match UnixStream::connect(&socket_path) {
        Ok(s) => s,
        Err(_) => {
            // DynamicMainland 未运行，静默退出（不阻塞 agent）
            return ExitCode::SUCCESS;
        }
    };

    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(120)))
        .ok();
    stream
        .set_write_timeout(Some(std::time::Duration::from_secs(5)))
        .ok();

    // 发送 session_start
    if let Ok(json) = serde_json::to_string(&start_event) {
        let _ = writeln!(stream, "{}", json);
        // 读取 ack
        let mut reader = BufReader::new(&stream);
        let mut line = String::new();
        let _ = reader.read_line(&mut line);
    }

    // 构建并发送主事件
    let event = match command {
        "pre-tool-use" => {
            let tool_name = hook_input
                .get("tool_name")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string();
            let tool_input = hook_input
                .get("tool_input")
                .cloned()
                .unwrap_or(serde_json::json!({}));

            HookEvent::PreToolUse {
                session_id,
                request_id,
                tool_name,
                tool_input,
            }
        }
        "post-tool-use" => {
            let tool_name = hook_input
                .get("tool_name")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string();
            let tool_input = hook_input
                .get("tool_input")
                .cloned()
                .unwrap_or(serde_json::json!({}));

            HookEvent::PostToolUse {
                session_id,
                tool_name,
                tool_input,
            }
        }
        "notification" => {
            let message = hook_input
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let level = hook_input
                .get("level")
                .and_then(|v| v.as_str())
                .unwrap_or("info")
                .to_string();

            HookEvent::Notification {
                session_id,
                level,
                message,
            }
        }
        _ => {
            eprintln!("dm-hook: 未知命令 '{}'", command);
            return ExitCode::FAILURE;
        }
    };

    let event_json = match serde_json::to_string(&event) {
        Ok(j) => j,
        Err(e) => {
            eprintln!("dm-hook: 序列化失败: {}", e);
            return ExitCode::FAILURE;
        }
    };

    if writeln!(stream, "{}", event_json).is_err() {
        return ExitCode::SUCCESS; // 连接断开，不阻塞 agent
    }

    // 读取响应
    let mut reader = BufReader::new(&stream);
    let mut response_line = String::new();
    match reader.read_line(&mut response_line) {
        Ok(0) | Err(_) => return ExitCode::SUCCESS,
        Ok(_) => {}
    }

    let response: HookResponse = match serde_json::from_str(&response_line) {
        Ok(r) => r,
        Err(_) => return ExitCode::SUCCESS,
    };

    match response {
        HookResponse::Ack => ExitCode::SUCCESS,
        HookResponse::Permission { approved } => {
            if approved {
                ExitCode::SUCCESS
            } else {
                // 非零退出码 = 拒绝工具使用
                ExitCode::from(2)
            }
        }
        HookResponse::Answer { text } => {
            // 将答案输出到 stdout 供 agent 读取
            println!("{}", text);
            ExitCode::SUCCESS
        }
        HookResponse::Error { message } => {
            eprintln!("dm-hook: 错误: {}", message);
            ExitCode::SUCCESS // 不阻塞 agent
        }
    }
}

fn get_arg(args: &[String], flag: &str) -> Option<String> {
    args.windows(2).find_map(|w| {
        if w[0] == flag {
            Some(w[1].clone())
        } else {
            None
        }
    })
}

fn generate_session_id() -> String {
    // 基于父进程 PID（agent 进程）生成稳定的 session ID
    let ppid = std::process::id(); // hook 进程的 PID
    let parent_ppid = get_parent_pid().unwrap_or(ppid);
    format!("session-{}", parent_ppid)
}

fn generate_request_id() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros())
        .unwrap_or(0);
    format!("req-{}-{}", std::process::id(), ts)
}

fn detect_terminal() -> String {
    // 检测当前运行的终端
    if std::env::var("ITERM_SESSION_ID").is_ok() {
        return "iTerm2".to_string();
    }
    if std::env::var("GHOSTTY_RESOURCES_DIR").is_ok() {
        return "Ghostty".to_string();
    }
    if std::env::var("WARP_IS_LOCAL_SHELL_SESSION").is_ok() {
        return "Warp".to_string();
    }
    if std::env::var("KITTY_PID").is_ok() {
        return "kitty".to_string();
    }
    if std::env::var("ALACRITTY_LOG").is_ok() {
        return "Alacritty".to_string();
    }
    if std::env::var("TERM_PROGRAM").ok().as_deref() == Some("vscode") {
        return "VSCode".to_string();
    }
    if std::env::var("TERM_PROGRAM").ok().as_deref() == Some("Apple_Terminal") {
        return "Terminal".to_string();
    }
    std::env::var("TERM_PROGRAM").unwrap_or_else(|_| "unknown".to_string())
}

fn get_parent_pid() -> Option<u32> {
    // macOS: 使用 sysctl 获取 ppid
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        let output = Command::new("ps")
            .args(["-o", "ppid=", "-p", &std::process::id().to_string()])
            .output()
            .ok()?;
        let ppid_str = String::from_utf8_lossy(&output.stdout);
        ppid_str.trim().parse().ok()
    }
    #[cfg(not(target_os = "macos"))]
    {
        None
    }
}
