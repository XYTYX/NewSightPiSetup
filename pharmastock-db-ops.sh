#!/bin/bash

# pharmastock-db-ops.sh
# Comprehensive database operations script for PharmaStock
# Handles seeding, backup script creation, and backup services

set -e  # Exit on any error

# Configuration
APP_NAME="PharmaStock"
CACHE_DIR="/var/cache/${APP_NAME}"
BACKUP_DIR="/opt/${APP_NAME}_backups"
DB_NAME="pharmastock.db"
DB_PATH="${CACHE_DIR}/${DB_NAME}"
BACKUP_SCRIPT="/opt/${APP_NAME}_backup.sh"

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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
    
    # Edge case 1: Check if backup file is readable and not empty
    if [ ! -r "${LATEST_BACKUP}" ]; then
        log "ERROR: Backup file is not readable: ${LATEST_BACKUP}"
        return 1
    fi
    
    if [ ! -s "${LATEST_BACKUP}" ]; then
        log "ERROR: Backup file is empty: ${LATEST_BACKUP}"
        return 1
    fi
    
    # Edge case 2: Check available disk space (need at least 200MB for safety)
    AVAILABLE_SPACE=$(df "${CACHE_DIR}" | awk 'NR==2 {print $4}')
    if [ "${AVAILABLE_SPACE}" -lt 204800 ]; then  # 200MB in KB
        log "ERROR: Insufficient disk space for database restoration (need 200MB, have ${AVAILABLE_SPACE}KB)"
        return 1
    fi
    
    # Edge case 3: Check if any process is using the database
    if command -v lsof >/dev/null 2>&1 && lsof "${DB_PATH}" >/dev/null 2>&1; then
        log "WARNING: Database file is in use by another process, waiting 5 seconds..."
        sleep 5
        if lsof "${DB_PATH}" >/dev/null 2>&1; then
            log "ERROR: Database file is still in use, skipping restoration"
            return 1
        fi
    fi
    
    # Check if sqlite3 is available
    if ! command -v sqlite3 >/dev/null 2>&1; then
        log "Installing sqlite3..."
        apt-get update
        apt-get install -y sqlite3
    fi
    
    # Edge case 4: Use atomic restoration with temporary file
    TEMP_DB="${DB_PATH}.tmp"
    
    # Extract and restore the database to temporary file
    log "Restoring database from backup..."
    if ! gunzip -c "${LATEST_BACKUP}" | sqlite3 "${TEMP_DB}"; then
        log "ERROR: Failed to extract and restore database from backup"
        rm -f "${TEMP_DB}"
        return 1
    fi
    
    # Edge case 5: Validate restored database integrity
    log "Validating restored database integrity..."
    if ! sqlite3 "${TEMP_DB}" "PRAGMA integrity_check;" | grep -q "ok"; then
        log "ERROR: Restored database failed integrity check"
        rm -f "${TEMP_DB}"
        return 1
    fi
    
    # Edge case 6: Atomic move to final location
    if ! mv "${TEMP_DB}" "${DB_PATH}"; then
        log "ERROR: Failed to move restored database to final location"
        rm -f "${TEMP_DB}"
        return 1
    fi
    
    # Set proper permissions
    chown root:root "${DB_PATH}"
    chmod 644 "${DB_PATH}"
    
    # Edge case 7: Final validation
    if ! sqlite3 "${DB_PATH}" "SELECT 1;" >/dev/null 2>&1; then
        log "ERROR: Final database validation failed"
        rm -f "${DB_PATH}"
        return 1
    fi
    
    log "Database successfully seeded from backup: $(basename "${LATEST_BACKUP}")"
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
    log "=== PharmaStock Database Operations Started ==="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # 1. Seed database from backup if needed
    seed_database_from_backup
    
    # 2. Create backup script
    create_backup_script
    
    # 3. Create backup systemd service and timer
    create_backup_service
    
    # 4. Create shutdown backup service
    create_shutdown_backup_service
    
    log "=== PharmaStock Database Operations Completed Successfully ==="
    log "Database operations configured:"
    log "  - Database seeding from backups"
    log "  - Daily backup script: ${BACKUP_SCRIPT}"
    log "  - Daily backup service: ${APP_NAME}-backup.timer"
    log "  - Shutdown backup service: ${APP_NAME}-shutdown-backup.service"
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
