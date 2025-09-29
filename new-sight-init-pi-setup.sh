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
    log "Setting up systemd service for initialization script..."
    
    # Get the current script path
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
    
    # Check if service already exists
    if systemctl list-unit-files | grep -q "new-sight-init.service"; then
        log "Service already exists, checking if update is needed..."
        
        # Check if the service file needs updating by comparing content
        CURRENT_SERVICE="/etc/systemd/system/new-sight-init.service"
        if [ -f "$CURRENT_SERVICE" ]; then
            # Create temporary file with new service content
            TEMP_SERVICE="/tmp/new-sight-init.service.tmp"
            cat > "$TEMP_SERVICE" << EOF
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
            
            # Compare files (ignore whitespace differences)
            if ! diff -q "$CURRENT_SERVICE" "$TEMP_SERVICE" > /dev/null 2>&1; then
                log "Service configuration has changed, updating..."
                cp "$TEMP_SERVICE" "$CURRENT_SERVICE"
                systemctl daemon-reload
                log "Service updated successfully"
            else
                log "Service configuration is up to date"
            fi
            
            # Clean up temporary file
            rm -f "$TEMP_SERVICE"
        else
            log "Service file missing, creating..."
            cat > "$CURRENT_SERVICE" << EOF
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
            systemctl daemon-reload
            log "Service created successfully"
        fi
    else
        log "Creating new systemd service..."
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
        systemctl daemon-reload
        log "Service created successfully"
    fi
    
    # Enable the service (idempotent operation)
    log "Enabling service..."
    systemctl enable new-sight-init.service
    
    # Check if service is enabled
    if systemctl is-enabled new-sight-init.service > /dev/null 2>&1; then
        log "Service is enabled and ready"
    else
        log "WARNING: Failed to enable service"
    fi
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
