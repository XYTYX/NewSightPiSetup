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
BACKUP_SCRIPT="/opt/${APP_NAME}_backup.sh"

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

# Function to seed database from most recent backup
seed_database_from_backup() {
    log "Checking if database needs to be seeded from backup..."
    
    # Check if database already exists in cache
    if [ -f "${DB_PATH}" ]; then
        log "Database already exists in cache, no seeding needed"
        return 0
    fi
    
    # Check if backup directory exists and has backups
    if [ ! -d "${BACKUP_DIR}" ]; then
        log "No backup directory found, skipping database seeding"
        return 0
    fi
    
    # Find the most recent backup file
    LATEST_BACKUP=$(find "${BACKUP_DIR}" -name "${DB_NAME}_*.db.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -z "${LATEST_BACKUP}" ]; then
        log "No backup files found, skipping database seeding"
        return 0
    fi
    
    log "Found latest backup: $(basename "${LATEST_BACKUP}")"
    
    # Check if sqlite3 is available
    if ! command -v sqlite3 >/dev/null 2>&1; then
        log "Installing sqlite3..."
        apt-get update
        apt-get install -y sqlite3
    fi
    
    # Extract and restore the database
    log "Restoring database from backup..."
    gunzip -c "${LATEST_BACKUP}" | sqlite3 "${DB_PATH}"
    
    # Set proper permissions
    chown root:root "${DB_PATH}"
    chmod 644 "${DB_PATH}"
    
    log "Database successfully seeded from backup: $(basename "${LATEST_BACKUP}")"
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

# Function to create backup script
create_backup_script() {
    log "Creating backup script..."
    
    cat > "${BACKUP_SCRIPT}" << 'EOF'
#!/bin/bash

# pharmastock_backup.sh
# Automated backup script for PharmaStock SQLite database

set -e

# Configuration
APP_NAME="PharmaStock"
CACHE_DIR="/var/cache/${APP_NAME}"
BACKUP_DIR="/opt/${APP_NAME}_backups"
DB_NAME="pharmastock.db"
DB_PATH="${CACHE_DIR}/${DB_NAME}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.db"

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to perform backup
perform_backup() {
    log "Starting daily backup process..."
    
    # Check if database exists
    if [ ! -f "${DB_PATH}" ]; then
        log "WARNING: Database not found at ${DB_PATH} - application may not have created it yet"
        return 0
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "${BACKUP_DIR}"
    
    # Perform the backup using sqlite3 .backup command
    log "Creating backup: ${BACKUP_FILE}"
    sqlite3 "${DB_PATH}" ".backup '${BACKUP_FILE}'"
    
    # Compress the backup
    log "Compressing backup..."
    gzip "${BACKUP_FILE}"
    BACKUP_FILE="${BACKUP_FILE}.gz"
    
    # Set proper permissions
    chown root:root "${BACKUP_FILE}"
    chmod 644 "${BACKUP_FILE}"
    
    log "Daily backup completed successfully: ${BACKUP_FILE}"
    
    # Clean up old backups (keep last 30 days)
    log "Cleaning up old backups..."
    find "${BACKUP_DIR}" -name "${DB_NAME}_*.db.gz" -type f -mtime +30 -delete
    
    log "Daily backup process completed"
}

# Main execution
main() {
    log "=== PharmaStock Daily Backup Started ==="
    perform_backup
    log "=== PharmaStock Daily Backup Completed ==="
}

# Run main function
main "$@"
EOF

    # Make the script executable
    chmod +x "${BACKUP_SCRIPT}"
    
    log "Backup script created at ${BACKUP_SCRIPT}"
}

# Function to create backup systemd service
create_backup_service() {
    log "Creating systemd service for daily backups..."
    
    cat > "/etc/systemd/system/${APP_NAME}-backup.service" << EOF
[Unit]
Description=PharmaStock Daily Database Backup
After=multi-user.target
RequiresMountsFor=${CACHE_DIR}

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
WorkingDirectory=${BACKUP_DIR}
User=root
StandardOutput=journal
StandardError=journal
EOF

    # Create backup timer for daily execution at 2:00 AM
    cat > "/etc/systemd/system/${APP_NAME}-backup.timer" << EOF
[Unit]
Description=Run PharmaStock backup daily at 2:00 AM
Requires=${APP_NAME}-backup.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable "${APP_NAME}-backup.timer"
    systemctl start "${APP_NAME}-backup.timer"
    
    log "Backup systemd service and timer created successfully"
    log "Backups will run daily at 2:00 AM with 5-minute random delay"
}

# Function to create shutdown backup service
create_shutdown_backup_service() {
    log "Creating systemd service for shutdown backups..."
    
    cat > "/etc/systemd/system/${APP_NAME}-shutdown-backup.service" << EOF
[Unit]
Description=PharmaStock Shutdown Database Backup
DefaultDependencies=false
Before=shutdown.target reboot.target halt.target
RequiresMountsFor=${CACHE_DIR}

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
WorkingDirectory=${BACKUP_DIR}
User=root
StandardOutput=journal
StandardError=journal
TimeoutStartSec=30
RemainAfterExit=yes

[Install]
WantedBy=shutdown.target reboot.target halt.target
EOF

    # Enable the shutdown backup service
    systemctl daemon-reload
    systemctl enable "${APP_NAME}-shutdown-backup.service"
    
    log "Shutdown backup service created and enabled successfully"
    log "Backups will run automatically on system shutdown/reboot"
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
    
    # 3. Seed database from backup if needed
    seed_database_from_backup
    
    # 4. Clone/update repository
    clone_repository
    
    # 5. Create backup script
    create_backup_script
    
    # 6. Create backup systemd service and timer
    create_backup_service
    
    # 7. Create shutdown backup service
    create_shutdown_backup_service
    
    log "=== PharmaStock Setup Completed Successfully ==="
    log "Repository directory: ${REPO_DIR}"
    log "Cache directory: ${CACHE_DIR}"
    log "Database will be created at: ${DB_PATH} (by your application)"
    log "Backup directory: ${BACKUP_DIR}"
    log "Backup script: ${BACKUP_SCRIPT}"
    log ""
    log "Service management commands:"
    log "  - Check backup status: systemctl status ${APP_NAME}-backup.timer"
    log "  - View backup logs: journalctl -u ${APP_NAME}-backup.service"
    log "  - Manual backup: systemctl start ${APP_NAME}-backup.service"
    log "  - Check timer: systemctl list-timers ${APP_NAME}-backup.timer"
    log "  - Check shutdown backup: systemctl status ${APP_NAME}-shutdown-backup.service"
    log "  - View shutdown logs: journalctl -u ${APP_NAME}-shutdown-backup.service"
}

# Run main function
main "$@"
