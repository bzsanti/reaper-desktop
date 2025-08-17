#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PLIST_NAME="com.reaper.menubar"
PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
APP_PATH="/Applications/ReaperMenuBar.app"

print_usage() {
    echo "Usage: $0 [install|uninstall|status|restart]"
    echo ""
    echo "Commands:"
    echo "  install   - Install ReaperMenuBar to start at login"
    echo "  uninstall - Remove ReaperMenuBar from startup"
    echo "  status    - Check if ReaperMenuBar is configured to start at login"
    echo "  restart   - Restart ReaperMenuBar service"
}

install_launch_agent() {
    echo -e "${YELLOW}Installing ReaperMenuBar startup service...${NC}"
    
    # Check if app exists
    if [ ! -d "$APP_PATH" ]; then
        echo -e "${RED}Error: ReaperMenuBar.app not found in /Applications${NC}"
        echo "Please run './deploy.sh --install' first"
        exit 1
    fi
    
    # Create LaunchAgent
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>${APP_PATH}/Contents/MacOS/ReaperMenuBar</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>
    
    <key>ProcessType</key>
    <string>Interactive</string>
    
    <key>Nice</key>
    <integer>10</integer>
    
    <key>StandardErrorPath</key>
    <string>/tmp/${PLIST_NAME}.err</string>
    
    <key>StandardOutPath</key>
    <string>/tmp/${PLIST_NAME}.out</string>
    
    <key>ThrottleInterval</key>
    <integer>30</integer>
</dict>
</plist>
EOF
    
    # Load the agent
    launchctl unload "$PLIST_FILE" 2>/dev/null
    launchctl load "$PLIST_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ ReaperMenuBar installed to start at login${NC}"
        echo -e "${GREEN}✓ ReaperMenuBar is now running in your menu bar${NC}"
    else
        echo -e "${RED}✗ Failed to load launch agent${NC}"
        exit 1
    fi
}

uninstall_launch_agent() {
    echo -e "${YELLOW}Removing ReaperMenuBar from startup...${NC}"
    
    if [ -f "$PLIST_FILE" ]; then
        # Unload the agent
        launchctl unload "$PLIST_FILE" 2>/dev/null
        
        # Remove the plist file
        rm "$PLIST_FILE"
        
        echo -e "${GREEN}✓ ReaperMenuBar removed from startup${NC}"
        
        # Kill any running instances
        pkill -f ReaperMenuBar 2>/dev/null
        echo -e "${GREEN}✓ Stopped running ReaperMenuBar instances${NC}"
    else
        echo -e "${YELLOW}ReaperMenuBar is not configured to start at login${NC}"
    fi
}

check_status() {
    echo -e "${YELLOW}Checking ReaperMenuBar startup status...${NC}"
    echo ""
    
    if [ -f "$PLIST_FILE" ]; then
        echo -e "${GREEN}✓ LaunchAgent is installed${NC}"
        echo "  Location: $PLIST_FILE"
        
        # Check if loaded
        if launchctl list | grep -q "$PLIST_NAME"; then
            echo -e "${GREEN}✓ Service is loaded and active${NC}"
            
            # Check if process is running
            if pgrep -f ReaperMenuBar > /dev/null; then
                echo -e "${GREEN}✓ ReaperMenuBar is currently running${NC}"
                
                # Show process info
                ps aux | grep -v grep | grep ReaperMenuBar | while read line; do
                    echo "  Process: $line"
                done
            else
                echo -e "${RED}✗ ReaperMenuBar is not running${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Service is installed but not loaded${NC}"
            echo "  Run: $0 restart"
        fi
    else
        echo -e "${YELLOW}ReaperMenuBar is not configured to start at login${NC}"
        echo "  To install: $0 install"
    fi
    
    echo ""
    echo "Log files:"
    echo "  stdout: /tmp/${PLIST_NAME}.out"
    echo "  stderr: /tmp/${PLIST_NAME}.err"
}

restart_service() {
    echo -e "${YELLOW}Restarting ReaperMenuBar service...${NC}"
    
    if [ ! -f "$PLIST_FILE" ]; then
        echo -e "${RED}Service is not installed${NC}"
        echo "Run: $0 install"
        exit 1
    fi
    
    # Unload and reload
    launchctl unload "$PLIST_FILE" 2>/dev/null
    sleep 1
    launchctl load "$PLIST_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Service restarted successfully${NC}"
    else
        echo -e "${RED}✗ Failed to restart service${NC}"
        exit 1
    fi
}

# Main logic
case "${1:-}" in
    install)
        install_launch_agent
        ;;
    uninstall)
        uninstall_launch_agent
        ;;
    status)
        check_status
        ;;
    restart)
        restart_service
        ;;
    *)
        print_usage
        exit 0
        ;;
esac