#!/bin/bash

set -e

echo "Building CPU Monitor..."

echo "Step 1: Building Rust core library..."
cd rust-core
cargo build --release
cd ..

echo "Step 2: Generating C headers..."
cd rust-core
cargo build --release
cd ..

echo "Step 3: Building Swift application..."
swift build -c release

echo "Build complete!"
echo "Run the application with: .build/release/CPUMonitor"