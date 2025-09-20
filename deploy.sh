#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Reaper Deployment System         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${YELLOW}➤ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to verify file size
verify_file_size() {
    local file=$1
    local min_size=$2
    local actual_size=$(stat -f%z "$file" 2>/dev/null || echo 0)
    
    if [ "$actual_size" -lt "$min_size" ]; then
        print_error "File $file is too small: ${actual_size} bytes (expected > ${min_size})"
        return 1
    fi
    return 0
}

# Function to kill existing processes
kill_existing_processes() {
    print_status "Stopping existing Reaper processes..."
    
    if pgrep -f ReaperApp > /dev/null; then
        pkill -f ReaperApp
        print_success "Stopped ReaperApp"
    fi
    
    if pgrep -f ReaperMenuBar > /dev/null; then
        pkill -f ReaperMenuBar
        print_success "Stopped ReaperMenuBar"
    fi
    
    sleep 1  # Give processes time to exit
}

# Function to clean build artifacts
clean_builds() {
    print_status "Cleaning previous builds..."
    
    # Clean Rust artifacts
    cargo clean 2>/dev/null || true
    
    # Clean Swift artifacts
    rm -rf ReaperApp/.build 2>/dev/null || true
    rm -rf ReaperMenuBar/.build 2>/dev/null || true
    
    # Clean old app bundles
    rm -rf Reaper.app 2>/dev/null || true
    rm -rf ../Reaper.app 2>/dev/null || true
    rm -rf ReaperMenuBar.app 2>/dev/null || true
    
    print_success "Cleaned build artifacts"
}

# Function to build Rust libraries
build_rust() {
    print_status "Building Rust libraries..."
    
    cargo build --release
    
    # Verify library sizes
    libraries=(
        "libreaper_core.dylib:5000"
        "libreaper_cpu_monitor.dylib:400000"
        "libreaper_memory_monitor.dylib:400000"
    )
    
    for lib_spec in "${libraries[@]}"; do
        IFS=':' read -r lib min_size <<< "$lib_spec"
        if ! verify_file_size "target/release/$lib" "$min_size"; then
            print_error "Failed to build $lib properly"
            exit 1
        fi
    done
    
    print_success "Rust libraries built successfully"
}

# Function to build ReaperApp
build_reaper_app() {
    print_status "Building ReaperApp..."
    
    cd ReaperApp
    swift build -c release -Xlinker -lreaper_memory_monitor
    
    if ! verify_file_size ".build/release/ReaperApp" 1000000; then
        print_error "ReaperApp executable is too small"
        cd ..
        exit 1
    fi
    
    cd ..
    print_success "ReaperApp built successfully"
}

# Function to build ReaperMenuBar
build_menubar() {
    print_status "Building ReaperMenuBar..."
    
    cd ReaperMenuBar
    swift build -c release
    
    if ! verify_file_size ".build/release/ReaperMenuBar" 500000; then
        print_error "ReaperMenuBar executable is too small"
        cd ..
        exit 1
    fi
    
    cd ..
    print_success "ReaperMenuBar built successfully"
}

# Function to create app bundle
create_app_bundle() {
    local app_name=$1
    local executable=$2
    local info_plist=$3
    local bundle_path=$4
    
    print_status "Creating $app_name bundle..."
    
    rm -rf "$bundle_path"
    mkdir -p "$bundle_path/Contents/MacOS"
    mkdir -p "$bundle_path/Contents/Resources"
    mkdir -p "$bundle_path/Contents/Frameworks"
    
    # Copy executable
    cp "$executable" "$bundle_path/Contents/MacOS/"
    
    # Copy Info.plist
    cp "$info_plist" "$bundle_path/Contents/Info.plist"
    
    # Copy icon if exists
    if [ -f "Resources/AppIcon.icns" ]; then
        cp "Resources/AppIcon.icns" "$bundle_path/Contents/Resources/"
    fi
    
    print_success "$app_name bundle created"
}

# Function to copy and verify libraries
copy_libraries() {
    local bundle_path=$1
    
    print_status "Copying libraries to $bundle_path..."
    
    for lib in target/release/*.dylib; do
        if [ -f "$lib" ]; then
            cp "$lib" "$bundle_path/Contents/Frameworks/"
            
            # Verify copy
            local basename=$(basename "$lib")
            local dest="$bundle_path/Contents/Frameworks/$basename"
            local src_size=$(stat -f%z "$lib")
            local dst_size=$(stat -f%z "$dest")
            
            if [ "$src_size" != "$dst_size" ]; then
                print_error "Library copy failed for $basename"
                exit 1
            fi
        fi
    done
    
    print_success "Libraries copied and verified"
}

# Function to sign app
sign_app() {
    local app_path=$1
    
    if command -v codesign &> /dev/null; then
        print_status "Signing $app_path..."
        codesign --force --deep --sign - "$app_path" 2>/dev/null || true
        print_success "App signed"
    fi
}

# Function to create version file
create_version_file() {
    local app_path=$1
    local version=$2
    
    echo "Version: $version" > "$app_path/Contents/Resources/VERSION"
    echo "Build Date: $(date)" >> "$app_path/Contents/Resources/VERSION"
    echo "Git Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')" >> "$app_path/Contents/Resources/VERSION"
}

# Main deployment process
main() {
    # Parse arguments
    CLEAN=false
    INSTALL=false
    LAUNCH=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN=true
                shift
                ;;
            --install)
                INSTALL=true
                shift
                ;;
            --launch)
                LAUNCH=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Kill existing processes
    kill_existing_processes
    
    # Clean if requested
    if [ "$CLEAN" = true ]; then
        clean_builds
    fi
    
    # Build everything
    build_rust
    build_reaper_app
    build_menubar
    
    # Create Reaper.app bundle
    create_app_bundle "Reaper" \
        "ReaperApp/.build/release/ReaperApp" \
        "ReaperApp/Info.plist" \
        "Reaper.app"
    
    copy_libraries "Reaper.app"
    create_version_file "Reaper.app" "0.3.0"
    sign_app "Reaper.app"
    
    # Create ReaperMenuBar.app bundle
    create_app_bundle "ReaperMenuBar" \
        "ReaperMenuBar/.build/release/ReaperMenuBar" \
        "ReaperMenuBar/Info.plist" \
        "ReaperMenuBar.app"
    
    copy_libraries "ReaperMenuBar.app"
    create_version_file "ReaperMenuBar.app" "0.3.0"
    sign_app "ReaperMenuBar.app"
    
    # Install to Applications if requested
    if [ "$INSTALL" = true ]; then
        print_status "Installing to /Applications..."
        
        sudo rm -rf /Applications/Reaper.app 2>/dev/null || true
        sudo cp -R Reaper.app /Applications/
        print_success "Reaper installed to /Applications"
        
        sudo rm -rf /Applications/ReaperMenuBar.app 2>/dev/null || true
        sudo cp -R ReaperMenuBar.app /Applications/
        print_success "ReaperMenuBar installed to /Applications"
    fi
    
    # Launch if requested
    if [ "$LAUNCH" = true ]; then
        print_status "Launching applications..."
        open Reaper.app
        open ReaperMenuBar.app
        print_success "Applications launched"
    fi
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Deployment Completed Successfully ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Options:"
    echo "  ./deploy.sh --clean    # Clean rebuild"
    echo "  ./deploy.sh --install  # Install to /Applications"
    echo "  ./deploy.sh --launch   # Launch after build"
    echo ""
}

# Run main function
main "$@"