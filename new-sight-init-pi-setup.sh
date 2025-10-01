#!/bin/bash

# new-sight-init-pi-setup.sh
# Simple initialization script that creates RAM folder and sets up startup
# This script should be placed in /boot/firmware/ for auto-execution on Pi boot

set -e  # Exit on any error

echo "Starting New Sight Pi initialization..."

# Repository configuration
REPO_URL="https://github.com/XYTYX/NewSightPiSetup.git"
REPO_DIR="/opt/NewSightPiSetup"

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to clone or update the repository
clone_repository() {
    log "Checking NewSightPiSetup repository..."
    
    # Install git if not present
    if ! command -v git &> /dev/null; then
        log "Installing git..."
        apt update
        apt install -y git
    fi
    
    # Check if repository directory exists
    if [ -d "$REPO_DIR" ]; then
        log "Repository directory exists, checking for updates..."
        
        # Change to repository directory
        cd "$REPO_DIR"
        
        # Check if it's a valid git repository
        if [ -d ".git" ]; then
            # Fetch latest changes from remote
            log "Fetching latest changes from remote..."
            git fetch origin
            
            # Get local and remote commit hashes
            LOCAL_COMMIT=$(git rev-parse HEAD)
            REMOTE_COMMIT=$(git rev-parse origin/main)
            
            log "Local commit: ${LOCAL_COMMIT:0:8}"
            log "Remote commit: ${REMOTE_COMMIT:0:8}"
            
            # Compare commits
            if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
                log "Repository is up to date, no changes needed"
                return 0
            else
                log "Repository has updates available, pulling changes..."
                git reset --hard origin/main
                log "Repository updated successfully"
            fi
        else
            log "Directory exists but is not a git repository, removing and cloning fresh..."
            cd /
            rm -rf "$REPO_DIR"
            clone_fresh_repository
        fi
    else
        log "Repository directory does not exist, cloning fresh..."
        clone_fresh_repository
    fi
}

# Function to clone fresh repository
clone_fresh_repository() {
    log "Cloning repository from $REPO_URL to $REPO_DIR (shallow copy)..."
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    
    if [ -d "$REPO_DIR" ]; then
        log "Repository cloned successfully (shallow copy)"
    else
        log "ERROR: Failed to clone repository"
        exit 1
    fi
}

# Function to run the main setup script
run_main_setup() {
    log "Running main setup script..."
    
    # Change to the repository directory
    cd "$REPO_DIR"
    
    # Check if the main setup script exists
    if [ ! -f "new-sight-pi-setup.sh" ]; then
        log "ERROR: new-sight-pi-setup.sh not found in repository"
        exit 1
    fi
    
    # Make the script executable
    chmod +x new-sight-pi-setup.sh
    
    # Run the main setup script with sudo
    log "Executing new-sight-pi-setup.sh with sudo..."
    sudo ./new-sight-pi-setup.sh
    
    log "Main setup script completed"
}

# Function to create systemd service for this initialization script
create_init_service() {
    log "Setting up systemd service for initialization script..."
    
    # Get the current script path
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
    
    # Create systemd service file
    cat > /etc/systemd/system/new-sight-init.service << EOF
[Unit]
Description=New Sight Pi Initialization Script
After=multi-user.target
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
User=root
Group=root
StandardOutput=journal
StandardError=journal
WorkingDirectory=$SCRIPT_DIR
TimeoutStartSec=300
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable new-sight-init.service
    
    log "Systemd service created and enabled successfully"
}

# Function to check and ensure root privileges
ensure_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        log "Please run with: sudo $0"
        exit 1
    fi
    log "Running with root privileges ✓"
}

# Main execution
main() {
    log "=== New Sight Pi Initialization Started ==="
    
    # Check if running as root
    ensure_root_privileges
    
    # 1. Set up to run on startup
    create_init_service
    
    # 2. Clone the repository
    clone_repository
    
    # 3. Run the main setup script
    run_main_setup
    
    log "=== New Sight Pi Initialization Completed Successfully ==="
    log ""
    log "Service management commands:"
    log "  - Check service status: systemctl status new-sight-init.service"
    log "  - View service logs: journalctl -u new-sight-init.service"
    log "  - Run service manually: systemctl start new-sight-init.service"
    log "  - Disable service: systemctl disable new-sight-init.service"
}

# Run main function
main "$@"