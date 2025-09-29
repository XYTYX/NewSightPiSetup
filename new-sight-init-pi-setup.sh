#!/bin/bash

# new-sight-init-pi-setup.sh
# Simple initialization script that creates RAM folder and sets up startup
# This script should be placed in /boot/firmware/ for auto-execution on Pi boot

set -e  # Exit on any error

echo "Starting New Sight Pi initialization..."

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to clone repository into RAM and run setup
setup_ram_folder() {
    log "Setting up NewSightPiSetup in RAM..."
    
    # Target directory for the repository (RAM disk to avoid boot media writes)
    REPO_DIR="/tmp/new-sight-pi-setup"
    GIT_REPO_URL="https://github.com/XYTYX/NewSightPiSetup.git"
    SETUP_SCRIPT="$REPO_DIR/new-sight-pi-setup.sh"

    log "Cloning repository from $GIT_REPO_URL to $REPO_DIR"

    # Clone directly into RAM folder
    git clone --depth 1 "$GIT_REPO_URL" "$REPO_DIR"
    
    # Make scripts executable
    chmod +x "$REPO_DIR"/*.sh
    
    # Run the main setup script
    if [ -f "$SETUP_SCRIPT" ]; then
        log "Running new-sight-pi-setup.sh from RAM..."
        cd "$REPO_DIR"
        "$SETUP_SCRIPT"
        log "Setup completed successfully"
    else
        log "ERROR: new-sight-pi-setup.sh not found in repository"
        exit 1
    fi
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

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
StandardOutput=journal
StandardError=journal
WorkingDirectory=$SCRIPT_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable new-sight-init.service
    
    log "Systemd service created and enabled successfully"
}

# Main execution
main() {
    log "=== New Sight Pi Initialization Started ==="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # 1. Create RAM folder with repository contents
    setup_ram_folder
    
    # 2. Set up to run on startup
    create_init_service
    
    log "=== New Sight Pi Initialization Completed Successfully ==="
}

# Run main function
main "$@"