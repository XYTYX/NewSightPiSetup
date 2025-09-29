#!/bin/bash

# new-sight-init-pi-setup.sh
# Initialization script that pulls the NewSightPiSetup repository and runs the main setup
# This script should be placed in /boot/firmware/ for auto-execution on Pi boot

set -e  # Exit on any error

echo "Starting New Sight Pi initialization..."

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check for updates and run setup
setup_new_sight() {
    log "Setting up New Sight Pi configuration..."
    
    # Target directory for the repository
    REPO_DIR="/opt/new-sight-pi-setup"
    REPO_URL="https://github.com/XYTYX/NewSightPiSetup.git"
    SETUP_SCRIPT="$REPO_DIR/new-sight-pi-setup.sh"
    
    # Create directory if it doesn't exist
    mkdir -p "$REPO_DIR"
    cd "$REPO_DIR"
    
    # Check if repository already exists
    if [ -d ".git" ]; then
        log "Repository exists, checking for updates..."
        
        # Get current local commit hash
        LOCAL_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "none")
        
        # Fetch latest changes without merging
        git fetch origin main
        
        # Get remote commit hash
        REMOTE_COMMIT=$(git rev-parse origin/main 2>/dev/null || echo "none")
        
        log "Local commit:  ${LOCAL_COMMIT:0:8}"
        log "Remote commit: ${REMOTE_COMMIT:0:8}"
        
        # Only update if commits are different
        if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
            log "New commits found, updating repository..."
            git pull origin main
            UPDATE_PERFORMED=true
        else
            log "Repository is up to date, no changes needed"
            UPDATE_PERFORMED=false
        fi
    else
        log "Cloning NewSightPiSetup repository..."
        git clone "$REPO_URL" .
        UPDATE_PERFORMED=true
    fi
    
    # Run the main setup script if it exists
    if [ -f "$SETUP_SCRIPT" ]; then
        log "Running new-sight-pi-setup.sh..."
        chmod +x "$SETUP_SCRIPT"
        "$SETUP_SCRIPT"
        log "New Sight Pi setup completed successfully"
    else
        log "ERROR: new-sight-pi-setup.sh not found in repository"
        exit 1
    fi
}

# Function to create systemd service for this initialization script
create_init_service() {
    log "Creating systemd service for initialization script..."
    
    # Get the current script path
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
    
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

    # Enable the service
    systemctl daemon-reload
    systemctl enable new-sight-init.service
    
    log "Initialization service created and enabled"
}

# Main execution
main() {
    log "=== New Sight Pi Initialization Started ==="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # Setup New Sight Pi
    setup_new_sight
    
    # Create systemd service for auto-startup
    create_init_service
    
    log "=== New Sight Pi Initialization Completed Successfully ==="
}

# Run main function
main "$@"
