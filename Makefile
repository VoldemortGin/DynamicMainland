.PHONY: all rust swift clean run install-hooks

all: rust swift

# 编译 Rust 静态库和 hook 客户端
rust:
	cargo build --release

# 编译 Swift 应用（依赖 Rust 静态库）
swift: rust
	swift build -c release

# 运行应用
run: all
	.build/release/DynamicMainland

# 安装 hook 到各 Agent 配置
install-hooks: all
	.build/release/DynamicMainland --install-hooks

clean:
	cargo clean
	swift package clean
	rm -rf .build
