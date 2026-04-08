#ifndef DYNAMIC_MAINLAND_H
#define DYNAMIC_MAINLAND_H

#include <stdbool.h>
#include <stdint.h>

/// 启动核心引擎（Unix socket 服务器）
void dm_start(void);

/// 停止核心引擎
void dm_stop(void);

/// 获取当前所有会话的 JSON 字符串，调用方需用 dm_free_string 释放
char* dm_get_sessions_json(void);

/// 获取待处理事件的 JSON 字符串，调用方需用 dm_free_string 释放
char* dm_get_pending_events_json(void);

/// 释放 Rust 分配的字符串
void dm_free_string(char* ptr);

/// 响应权限请求: approved = true 表示批准
void dm_respond_permission(const char* session_id, const char* request_id, bool approved);

/// 响应用户问题
void dm_respond_question(const char* session_id, const char* request_id, const char* answer);

/// 为所有检测到的 Agent 安装 hook
void dm_install_hooks(void);

/// 检查 hook 是否已安装
bool dm_hooks_installed(void);

/// 跳转到指定会话的终端
void dm_jump_to_terminal(const char* session_id);

/// 获取 hook 客户端二进制路径，调用方需用 dm_free_string 释放
char* dm_get_hook_client_path(void);

/// 获取 socket 路径，调用方需用 dm_free_string 释放
char* dm_get_socket_path(void);

#endif // DYNAMIC_MAINLAND_H
