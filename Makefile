# CPU Limiting Configuration
CORES := $(shell sysctl -n hw.ncpu)
MAX_JOBS := $(shell echo $$(($(CORES) / 2)))
ifeq ($(shell [ $(MAX_JOBS) -gt 0 ] && echo yes),yes)
  JOBS := $(MAX_JOBS)
else
  JOBS := 1
endif

.PHONY: all build-rust build-swift clean run open build-safe test-safe

all: build-rust build-swift

# Standard build targets
build-rust:
	@echo "Building Rust libraries..."
	cargo build --release

build-swift: build-rust
	@echo "Building Swift application..."
	cd ReaperApp && swift build -c release

# Safe build targets with CPU limits (prevents system blocking)
build-safe:
	@echo "🔧 Safe Build Mode: Using $(JOBS) of $(CORES) cores (50%)"
	@echo "Building Rust libraries with CPU limit..."
	@nice -n 10 cargo build --release -j $(JOBS)
	@echo "Building Swift application with CPU limit..."
	@cd ReaperApp && nice -n 10 swift build -c release -j $(JOBS)

build-rust-safe:
	@echo "Building Rust with $(JOBS) jobs (50% of $(CORES) cores)"
	@nice -n 10 cargo build --release -j $(JOBS)

build-swift-safe: build-rust-safe
	@echo "Building Swift with $(JOBS) jobs (50% of $(CORES) cores)"
	@cd ReaperApp && nice -n 10 swift build -c release -j $(JOBS)

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

# Safe test target with CPU limits
test-safe:
	@echo "Testing with $(JOBS) jobs (50% of $(CORES) cores)"
	@nice -n 10 cargo test -j $(JOBS)
	@cd ReaperApp && nice -n 10 swift test -j $(JOBS)