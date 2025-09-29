#!/bin/bash

# new-sight-pi-setup.sh
# Script to configure Raspberry Pi for general use
# Run this script from /boot/firmware on startup

set -e  # Exit on any error

echo "Starting Pi setup script..."

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
}

# Function to configure journald for log rotation
configure_journald() {
    log "Configuring journald for log rotation..."
    
    # Backup original configuration
    cp /etc/systemd/journald.conf /etc/systemd/journald.conf.backup
    
    # Create minimal journald configuration for log rotation
    cat > /etc/systemd/journald.conf << 'EOF'
[Journal]
# Log rotation settings
SystemMaxUse=50M
SystemMaxFileSize=10M
MaxRetentionSec=14d
EOF

    log "Restarting journald service..."
    systemctl restart systemd-journald
    
    if systemctl is-active --quiet systemd-journald; then
        log "journald service restarted successfully"
    else
        log "ERROR: Failed to restart journald service"
        exit 1
    fi
}

# Function to install and configure log2ram
install_log2ram() {
    log "Checking if log2ram is installed..."
    
    if command -v log2ram &> /dev/null; then
        log "log2ram is already installed"
    else
        log "Installing log2ram..."
        
        # Update package list
        apt update
        
        # Install log2ram
        curl -Lo log2ram.tar.gz https://github.com/azlux/log2ram/archive/master.tar.gz
        tar xf log2ram.tar.gz
        cd log2ram-master
        chmod +x install.sh
        ./install.sh
        cd ..
        rm -rf log2ram-master log2ram.tar.gz
        
        log "log2ram installed successfully"
    fi
    
    # Enable log2ram service
    log "Enabling log2ram service..."
    systemctl enable log2ram
    systemctl start log2ram
    
    if systemctl is-active --quiet log2ram; then
        log "log2ram service started successfully"
    else
        log "WARNING: log2ram service may not have started properly"
    fi
}

# Function to install and configure nginx
install_nginx() {
    log "Checking if nginx is installed..."
    
    if command -v nginx &> /dev/null; then
        log "nginx is already installed"
    else
        log "Installing nginx..."
        
        # Update package list
        apt update
        
        # Install nginx
        apt install -y nginx
        
        log "nginx installed successfully"
    fi
    
    # Enable nginx service
    log "Enabling nginx service..."
    systemctl enable nginx
    systemctl start nginx
    
    if systemctl is-active --quiet nginx; then
        log "nginx service started successfully"
    else
        log "ERROR: Failed to start nginx service"
        exit 1
    fi
}

# Function to configure nginx
configure_nginx() {
    log "Configuring nginx for new-sight.local..."
    
    # Backup original nginx configuration
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    
    # Create basic nginx configuration
    cat > /etc/nginx/sites-available/new-sight << 'EOF'
server {
    listen 80;
    server_name new-sight.local;
    
    # Default location - can be configured by separate files
    location / {
        return 200 'nginx is running on new-sight.local';
        add_header Content-Type text/plain;
    }
}
EOF

    # Enable the site configuration
    ln -sf /etc/nginx/sites-available/new-sight /etc/nginx/sites-enabled/
    
    # Remove default nginx site if it exists
    if [ -f /etc/nginx/sites-enabled/default ]; then
        rm /etc/nginx/sites-enabled/default
        log "Removed default nginx site"
    fi
    
    # Test nginx configuration
    log "Testing nginx configuration..."
    if nginx -t; then
        log "nginx configuration test passed"
        
        # Reload nginx to apply changes
        systemctl reload nginx
        log "nginx configuration reloaded successfully"
    else
        log "ERROR: nginx configuration test failed"
        exit 1
    fi
}

# Function to create systemd service for this script
create_startup_service() {
    log "Creating systemd service for Pi setup script..."
    
    # Get the current script path
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
    
    cat > /etc/systemd/system/new-sight-pi-setup.service << EOF
[Unit]
Description=New Sight Pi Setup Script
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
    systemctl enable new-sight-pi-setup.service
    
    log "Pi setup service created and enabled"
}

# Function to setup PharmaStock application
setup_pharmastock() {
    log "Setting up PharmaStock application..."
    
    # Create directory for the application
    APP_DIR="/opt/pharmastock"
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Check if repository already exists
    if [ -d ".git" ]; then
        log "PharmaStock repository exists, checking for updates..."
        
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
        log "Cloning PharmaStock repository..."
        git clone https://github.com/XYTYX/PharmaStock.git .
        UPDATE_PERFORMED=true
    fi
    
    # Run setup-pi.sh if it exists
    if [ -f "setup-pi.sh" ]; then
        log "Running setup-pi.sh script..."
        chmod +x setup-pi.sh
        ./setup-pi.sh
        log "PharmaStock setup-pi.sh completed successfully"
    else
        log "WARNING: setup-pi.sh not found in PharmaStock repository"
    fi
}

# Main execution
main() {
    log "=== Pi Setup Script Started ==="
    
    # Check if running as root
    check_root
    
    # Step 1: Configure journald
    configure_journald
    
    # Step 2: Install and configure log2ram
    install_log2ram
    
    # Step 3: Install and configure nginx
    install_nginx
    
    # Step 4: Configure nginx
    configure_nginx
    
    # Step 5: Create systemd service for auto-startup
    create_startup_service
    
    # Step 6: Setup PharmaStock application
    setup_pharmastock
    
    log "=== Pi Setup Script Completed Successfully ==="
}

# Run main function
main "$@"
