use std::process::Command;

/// 支持的终端应用
pub enum TerminalApp {
    ITerm2,
    Terminal,
    Ghostty,
    Warp,
    Alacritty,
    Kitty,
    VSCode,
    CursorEditor,
}

impl TerminalApp {
    pub fn from_name(name: &str) -> Option<Self> {
        match name.to_lowercase().as_str() {
            "iterm2" | "iterm" => Some(Self::ITerm2),
            "terminal" | "terminal.app" => Some(Self::Terminal),
            "ghostty" => Some(Self::Ghostty),
            "warp" => Some(Self::Warp),
            "alacritty" => Some(Self::Alacritty),
            "kitty" => Some(Self::Kitty),
            "vscode" | "code" | "visual studio code" => Some(Self::VSCode),
            "cursor" => Some(Self::CursorEditor),
            _ => None,
        }
    }

    pub fn bundle_id(&self) -> &'static str {
        match self {
            Self::ITerm2 => "com.googlecode.iterm2",
            Self::Terminal => "com.apple.Terminal",
            Self::Ghostty => "com.mitchellh.ghostty",
            Self::Warp => "dev.warp.Warp-Stable",
            Self::Alacritty => "org.alacritty",
            Self::Kitty => "net.kovidgoyal.kitty",
            Self::VSCode => "com.microsoft.VSCode",
            Self::CursorEditor => "com.todesktop.230313mzl4w4u92",
        }
    }
}

/// 跳转到指定终端窗口
pub fn jump_to_terminal(terminal_app: &str, terminal_id: &str) -> Result<(), String> {
    let app = TerminalApp::from_name(terminal_app);

    match app {
        Some(TerminalApp::ITerm2) => jump_iterm2(terminal_id),
        Some(TerminalApp::Terminal) => jump_terminal_app(terminal_id),
        Some(TerminalApp::Ghostty) => activate_app("Ghostty"),
        Some(TerminalApp::Warp) => activate_app("Warp"),
        Some(TerminalApp::Alacritty) => activate_app("Alacritty"),
        Some(TerminalApp::Kitty) => activate_app("kitty"),
        Some(TerminalApp::VSCode) => activate_app("Visual Studio Code"),
        Some(TerminalApp::CursorEditor) => activate_app("Cursor"),
        None => activate_app(terminal_app),
    }
}

/// 通过 AppleScript 激活应用
fn activate_app(app_name: &str) -> Result<(), String> {
    let script = format!(
        r#"tell application "{}" to activate"#,
        app_name.replace('"', "\\\"")
    );
    run_applescript(&script)
}

/// iTerm2 特定跳转（支持标签页和分割面板）
fn jump_iterm2(terminal_id: &str) -> Result<(), String> {
    // terminal_id 格式: "tab:N:pane:M" 或简单的窗口标识
    let script = if terminal_id.contains("tab:") {
        // 解析 tab 和 pane
        let parts: Vec<&str> = terminal_id.split(':').collect();
        let tab_idx = parts.get(1).unwrap_or(&"0");
        format!(
            r#"
            tell application "iTerm2"
                activate
                tell current window
                    select tab {}
                end tell
            end tell
            "#,
            tab_idx
        )
    } else {
        r#"tell application "iTerm2" to activate"#.to_string()
    };

    run_applescript(&script)
}

/// Terminal.app 跳转
fn jump_terminal_app(_terminal_id: &str) -> Result<(), String> {
    let script = format!(
        r#"
        tell application "Terminal"
            activate
            set index of window 1 to 1
        end tell
        "#
    );
    run_applescript(&script)
}

fn run_applescript(script: &str) -> Result<(), String> {
    Command::new("osascript")
        .arg("-e")
        .arg(script)
        .output()
        .map_err(|e| format!("AppleScript 执行失败: {}", e))
        .and_then(|output| {
            if output.status.success() {
                Ok(())
            } else {
                Err(format!(
                    "AppleScript 错误: {}",
                    String::from_utf8_lossy(&output.stderr)
                ))
            }
        })
}
