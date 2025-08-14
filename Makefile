.PHONY: all build-rust build-swift clean run open

all: build-rust build-swift

build-rust:
	@echo "Building Rust libraries..."
	cargo build --release

build-swift: build-rust
	@echo "Building Swift application..."
	cd ReaperApp && swift build -c release

run: all
	@echo "Running Reaper..."
	./ReaperApp/.build/release/ReaperApp

open: all
	@echo "Opening Reaper app..."
	open ./ReaperApp/.build/release/ReaperApp

clean:
	@echo "Cleaning build artifacts..."
	cargo clean
	cd ReaperApp && swift package clean
	rm -rf ReaperApp/.build

test:
	cargo test
	cd ReaperApp && swift test