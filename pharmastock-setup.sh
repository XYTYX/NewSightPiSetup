#!/bin/bash

# pharmastock-setup.sh
# PharmaStock-specific setup script for repository cloning and application configuration
# PharmaStock currently runs on a Raspberry Pi, so I want to reduce the number of writes/reads on disk

set -e  # Exit on any error

# Configuration
APP_NAME="PharmaStock"
CACHE_DIR="/var/cache/${APP_NAME}"
BACKUP_DIR="/opt/${APP_NAME}_backups"
DB_NAME="pharmastock.db"
DB_PATH="${CACHE_DIR}/${DB_NAME}"

# Repository configuration
REPO_URL="https://github.com/XYTYX/PharmaStock.git"
REPO_DIR="/opt/${APP_NAME}"

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to create tmpfs cache directory
setup_cache_directory() {
    log "Setting up tmpfs cache directory for application data..."
    
    # Create tmpfs mount point
    if ! grep -q "${CACHE_DIR}" /etc/fstab; then
        log "Adding tmpfs entry to /etc/fstab..."
        echo "tmpfs ${CACHE_DIR} tmpfs defaults,size=100M,noatime,nosuid,nodev,noexec,mode=755 0 0" >> /etc/fstab
    fi
    
    # Create the directory
    mkdir -p "${CACHE_DIR}"
    
    # Mount the tmpfs
    if ! mountpoint -q "${CACHE_DIR}"; then
        log "Mounting tmpfs to ${CACHE_DIR}..."
        mount "${CACHE_DIR}"
    fi
    
    # Set proper permissions
    chown root:root "${CACHE_DIR}"
    chmod 755 "${CACHE_DIR}"
    
    log "Cache directory ${CACHE_DIR} created and mounted successfully"
}

# Function to create backup directory
setup_backup_directory() {
    log "Setting up backup directory..."
    
    mkdir -p "${BACKUP_DIR}"
    chown root:root "${BACKUP_DIR}"
    chmod 755 "${BACKUP_DIR}"
    
    log "Backup directory ${BACKUP_DIR} created successfully"
}

# Function to run database operations
run_database_operations() {
    log "Running database operations script..."
    
    # Check if pharmastock-db-ops.sh exists
    if [ ! -f "./pharmastock-db-ops.sh" ]; then
        log "ERROR: pharmastock-db-ops.sh not found in current directory"
        exit 1
    fi
    
    # Make the script executable
    chmod +x pharmastock-db-ops.sh
    
    # Run the database operations script
    log "Executing pharmastock-db-ops.sh..."
    sudo ./pharmastock-db-ops.sh
    
    log "Database operations completed"
}

# Function to run nginx setup
run_nginx_setup() {
    log "Running nginx setup script..."
    
    # Check if nginx-setup.sh exists
    if [ ! -f "./nginx-setup.sh" ]; then
        log "ERROR: nginx-setup.sh not found in current directory"
        exit 1
    fi
    
    # Make the script executable
    chmod +x nginx-setup.sh
    
    # Run the nginx setup script
    log "Executing nginx-setup.sh..."
    sudo ./nginx-setup.sh
    
    log "Nginx setup completed"
}

# Function to clone or update the repository
clone_repository() {
    log "Checking PharmaStock repository..."
    
    # Install git if not present
    if ! command -v git &> /dev/null; then
        log "Installing git..."
        apt-get update
        apt-get install -y git
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
                git pull origin main
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

# Main execution
main() {
    log "=== PharmaStock Setup Started ==="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # 1. Setup cache directory (tmpfs)
    setup_cache_directory
    
    # 2. Setup backup directory
    setup_backup_directory
    
    # 3. Run database operations (seeding, backup script, services)
    run_database_operations
    
    # 4. Clone/update repository
    clone_repository
    
    # 5. Run nginx setup
    run_nginx_setup

    log "=== PharmaStock Setup Completed Successfully ==="
    log "Repository directory: ${REPO_DIR}"
    log "Cache directory: ${CACHE_DIR}"
    log "Database will be created at: ${DB_PATH} (by your application)"
    log "Backup directory: ${BACKUP_DIR}"
    log ""
    log "All database operations have been configured:"
    log "  - Database seeding from backups"
    log "  - Daily backup system"
    log "  - Shutdown backup system"
    log ""
    log "Nginx reverse proxy has been configured:"
    log "  - Access your application at: http://new-sight.local/"
    log "  - Backend: localhost:3000"
    log "  - Configuration: /etc/nginx/sites-available/new-sight"
}

# Run main function
main "$@"