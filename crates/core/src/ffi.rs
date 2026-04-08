use crate::hooks;
use crate::server::Server;
use crate::session::SessionManager;
use crate::terminal;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;
use std::thread;

struct Engine {
    server: Server,
    session_mgr: SessionManager,
}

static ENGINE: OnceLock<Engine> = OnceLock::new();

fn get_engine() -> &'static Engine {
    ENGINE.get_or_init(|| {
        let session_mgr = SessionManager::new();
        let server = Server::new(session_mgr.clone());
        Engine {
            server,
            session_mgr,
        }
    })
}

#[no_mangle]
pub extern "C" fn dm_start() {
    let engine = get_engine();
    if engine.server.is_running() {
        return;
    }
    // 在后台线程启动服务器
    let server_ref = &engine.server as *const Server as usize;
    thread::spawn(move || {
        let server = unsafe { &*(server_ref as *const Server) };
        server.start();
    });
}

#[no_mangle]
pub extern "C" fn dm_stop() {
    if let Some(engine) = ENGINE.get() {
        engine.server.stop();
    }
}

#[no_mangle]
pub extern "C" fn dm_get_sessions_json() -> *mut c_char {
    let engine = get_engine();
    let json = engine.session_mgr.get_all_sessions_json();
    string_to_c(json)
}

#[no_mangle]
pub extern "C" fn dm_get_pending_events_json() -> *mut c_char {
    let engine = get_engine();
    let json = engine.server.get_pending_events_json();
    string_to_c(json)
}

#[no_mangle]
pub extern "C" fn dm_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn dm_respond_permission(
    session_id: *const c_char,
    request_id: *const c_char,
    approved: bool,
) {
    let engine = get_engine();
    let _session_id = unsafe { CStr::from_ptr(session_id) }
        .to_string_lossy()
        .to_string();
    let request_id = unsafe { CStr::from_ptr(request_id) }
        .to_string_lossy()
        .to_string();
    engine.server.respond_permission(&request_id, approved);
}

#[no_mangle]
pub extern "C" fn dm_respond_question(
    session_id: *const c_char,
    request_id: *const c_char,
    answer: *const c_char,
) {
    let engine = get_engine();
    let _session_id = unsafe { CStr::from_ptr(session_id) }
        .to_string_lossy()
        .to_string();
    let request_id = unsafe { CStr::from_ptr(request_id) }
        .to_string_lossy()
        .to_string();
    let answer = unsafe { CStr::from_ptr(answer) }
        .to_string_lossy()
        .to_string();
    engine.server.respond_question(&request_id, &answer);
}

#[no_mangle]
pub extern "C" fn dm_install_hooks() {
    let engine = get_engine();
    let hook_path = get_hook_client_path();
    let socket_path = engine.server.socket_path().to_string();
    let results = hooks::install_all_hooks(&hook_path, &socket_path);
    for (agent, result) in results {
        match result {
            Ok(()) => eprintln!("[DM] {} hook 安装成功", agent.display_name()),
            Err(e) => eprintln!("[DM] {} hook 安装失败: {}", agent.display_name(), e),
        }
    }
}

#[no_mangle]
pub extern "C" fn dm_hooks_installed() -> bool {
    hooks::is_hook_installed(crate::agent::AgentKind::ClaudeCode)
}

#[no_mangle]
pub extern "C" fn dm_jump_to_terminal(session_id: *const c_char) {
    let engine = get_engine();
    let session_id = unsafe { CStr::from_ptr(session_id) }
        .to_string_lossy()
        .to_string();
    if let Some(session) = engine.session_mgr.get_session(&session_id) {
        if let Err(e) = terminal::jump_to_terminal(&session.terminal_app, &session.terminal_id) {
            eprintln!("[DM] 终端跳转失败: {}", e);
        }
    }
}

#[no_mangle]
pub extern "C" fn dm_get_hook_client_path() -> *mut c_char {
    string_to_c(get_hook_client_path())
}

#[no_mangle]
pub extern "C" fn dm_get_socket_path() -> *mut c_char {
    let engine = get_engine();
    string_to_c(engine.server.socket_path().to_string())
}

fn get_hook_client_path() -> String {
    // 尝试找到 dm-hook 二进制
    // 优先查找与当前可执行文件同目录
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let hook_path = dir.join("dm-hook");
            if hook_path.exists() {
                return hook_path.to_string_lossy().to_string();
            }
        }
    }
    // 回退到 PATH 中查找
    "dm-hook".to_string()
}

fn string_to_c(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}
