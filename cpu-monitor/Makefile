.PHONY: all build-rust build-swift clean run

all: build-rust build-swift

build-rust:
	@echo "Building Rust core library..."
	cd rust-core && cargo build --release

build-swift: build-rust
	@echo "Building Swift application..."
	swift build -c release

run: all
	@echo "Running CPU Monitor..."
	.build/release/CPUMonitor

clean:
	@echo "Cleaning build artifacts..."
	cd rust-core && cargo clean
	swift package clean
	rm -rf .build

debug:
	cd rust-core && cargo build
	swift build
	.build/debug/CPUMonitor