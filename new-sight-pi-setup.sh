#!/bin/bash

# new-sight-pi-setup.sh
# Generic setup script for tmpfs cache directory and log2ram installation

set -e  # Exit on any error

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to install log2ram if not exists
install_log2ram() {
    log "Checking for log2ram installation..."
    
    # Check if log2ram is already installed
    if command -v log2ram >/dev/null 2>&1; then
        log "log2ram is already installed"
        return 0
    fi
    
    log "log2ram not found, installing..."
    
    # Update package list
    apt-get update
    
    # Install log2ram
    apt-get install -y log2ram
    
    # Enable and start log2ram service
    systemctl enable log2ram
    systemctl start log2ram
    
    log "log2ram installed and started successfully"
}

# Function to run PharmaStock setup
run_pharmastock_setup() {
    log "Running PharmaStock setup..."
    
    # Check if pharmastock-setup.sh exists
    if [ ! -f "./pharmastock-setup.sh" ]; then
        log "ERROR: pharmastock-setup.sh not found in current directory"
        exit 1
    fi
    
    # Make the script executable
    chmod +x pharmastock-setup.sh
    
    # Run the PharmaStock setup script
    log "Executing pharmastock-setup.sh..."
    sudo ./pharmastock-setup.sh
    
    log "PharmaStock setup completed"
}

# Main execution
main() {
    log "=== New Sight Pi Setup Started ==="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # 1. Install log2ram if not exists
    install_log2ram
    
    # 2. Run PharmaStock setup
    run_pharmastock_setup
    
    log "=== New Sight Pi Setup Completed Successfully ==="
    log ""
    log "System is now configured with:"
    log "  - log2ram for SD card protection"
    log "  - PharmaStock application setup"
    log ""
    log "Service management commands:"
    log "  - Check log2ram status: systemctl status log2ram"
    log "  - View log2ram logs: journalctl -u log2ram"
    log "  - Check PharmaStock backup: systemctl status PharmaStock-backup.timer"
    log "  - View PharmaStock logs: journalctl -u PharmaStock-backup.service"
}

# Run main function
main "$@"