#!/bin/bash

# new-sight-pi-setup.sh
# Script to configure Raspberry Pi for general use
# This script is run by the new-sight-init.service systemd service

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
    log "Configuring journald for minimal boot media writes..."
    
    # Backup original configuration
    cp /etc/systemd/journald.conf /etc/systemd/journald.conf.backup
    
    # Create minimal journald configuration for log rotation
    cat > /etc/systemd/journald.conf << 'EOF'
[Journal]
# Aggressive log rotation settings to minimize boot media writes
SystemMaxUse=25M
SystemMaxFileSize=5M
MaxRetentionSec=7d
# Store logs in RAM only (no persistent storage)
Storage=volatile
# Reduce sync frequency
SyncIntervalSec=300
# Compress logs
Compress=yes
# Limit number of files
SystemMaxFiles=5
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

# Function to configure additional tmpfs mounts for write reduction
configure_tmpfs_mounts() {
    log "Configuring additional tmpfs mounts to reduce boot media writes..."
    
    # Create fstab entries for streamlined tmpfs mounts (16GB RAM optimized)
    TMPFS_ENTRIES="
# Streamlined tmpfs mounts to reduce boot media writes (16GB RAM optimized)
# Core system directories
tmpfs /tmp tmpfs defaults,noatime,size=1G 0 0
tmpfs /var/log tmpfs defaults,noatime,size=500M 0 0

# Unified cache directory for all caches
tmpfs /var/cache tmpfs defaults,noatime,size=2G 0 0

# Application-specific directories
tmpfs /opt/pharmastock tmpfs defaults,noatime,size=2G 0 0
tmpfs /opt/new-sight-pi-setup tmpfs defaults,noatime,size=1G 0 0
tmpfs /opt/cache tmpfs defaults,noatime,size=1G 0 0
"
    
    # Add entries to fstab if they don't exist
    echo "$TMPFS_ENTRIES" >> /etc/fstab
    
    # Mount the new tmpfs filesystems
    mount -a
    
    log "Additional tmpfs mounts configured successfully"
}

# Function to configure zram for swap (RAM-based swap instead of disk)
configure_zram_swap() {
    log "Configuring zram for RAM-based swap..."
    
    # Install zram-tools if not present
    if ! command -v zramctl &> /dev/null; then
        log "Installing zram-tools..."
        apt update
        apt install -y zram-tools
    fi
    
    # Configure zram for swap (use 25% of RAM for swap)
    cat > /etc/default/zramswap << 'EOF'
# Zram configuration for 16GB RAM system
ALGO=lz4
PERCENT=25
PRIORITY=100
EOF
    
    # Enable and start zram
    systemctl enable zramswap
    systemctl start zramswap
    
    if systemctl is-active --quiet zramswap; then
        log "zram swap configured successfully"
        zramctl
    else
        log "WARNING: zram swap may not have started properly"
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

    # Check if nginx is running, if so, stop it gracefully
    if systemctl is-active --quiet nginx; then
        log "nginx is already running, stopping it gracefully..."
        systemctl stop nginx
        sleep 2
    fi

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
    
    # Create nginx configuration with pharmacy proxy
    cat > /etc/nginx/sites-available/new-sight << 'EOF'
server {
    listen 80;
    server_name new-sight.local;
    
    # Proxy configuration for /pharmacy path to PharmaStock frontend
    location /pharmacy {
        proxy_pass http://127.0.0.1:3001/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_redirect off;
    }
    
    # Default location for other requests
    location / {
        return 200 'nginx is running on new-sight.local - visit /pharmacy for PharmaStock';
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


# Function to setup PharmaStock application (Binary-based approach)
setup_pharmastock() {
    log "Setting up PharmaStock application using binary approach..."
    
    # Create RAM disk for application (tmpfs - no writes to boot media)
    APP_DIR="/opt/pharmastock"
    CACHE_DIR="/opt/cache/pharmastock"
    log "Creating RAM disk for PharmaStock application at $APP_DIR..."
    
    # Create cache subdirectory
    mkdir -p "$CACHE_DIR"
    
    cd "$APP_DIR"
    
    # Check if we have a cached version
    VERSION_FILE="$CACHE_DIR/pharmastock-version.txt"
    CURRENT_VERSION=""
    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
    fi
    
    # Get latest release info from GitHub API (minimal data transfer)
    log "Checking for PharmaStock updates..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/XYTYX/PharmaStock/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then
        log "WARNING: Could not fetch latest version, using fallback approach"
        LATEST_VERSION="main"
    fi
    
    log "Current version: ${CURRENT_VERSION:-none}"
    log "Latest version: $LATEST_VERSION"
    
    # Only download if version changed or no cached version exists
    if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        log "Version mismatch, downloading PharmaStock..."
        
        # Download source as tarball (more efficient than git clone)
        DOWNLOAD_URL="https://github.com/XYTYX/PharmaStock/archive/refs/heads/main.tar.gz"
        log "Downloading PharmaStock source..."
        
        # Download to cache first, then extract to app directory
        curl -L -o "$CACHE_DIR/pharmastock.tar.gz" "$DOWNLOAD_URL"
        
        # Extract to app directory
        tar -xzf "$CACHE_DIR/pharmastock.tar.gz" --strip-components=1 -C "$APP_DIR"
        
        # Save version info
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        
        # Clean up download
        rm -f "$CACHE_DIR/pharmastock.tar.gz"
        
        UPDATE_PERFORMED=true
        log "PharmaStock downloaded and extracted successfully"
    else
        log "PharmaStock is up to date, no download needed"
        UPDATE_PERFORMED=false
    fi
    
    # Run setup-pi.sh if it exists
    # TODO: Uncomment  
    # if [ -f "setup-pi.sh" ]; then
    #     log "Running setup-pi.sh script..."
    #     chmod +x setup-pi.sh
    #     ./setup-pi.sh
    #     log "PharmaStock setup-pi.sh completed successfully"
    # else
    #     log "WARNING: setup-pi.sh not found in PharmaStock repository"
    # fi

    #TODO: uncomment
    # start_pharmastock_services
}

# Function to start PharmaStock services
start_pharmastock_services() {
    log "Starting PharmaStock services..."
    
    APP_DIR="/opt/pharmastock"
    cd "$APP_DIR"
    
    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        log "ERROR: package.json not found in PharmaStock directory"
        return 1
    fi
    
    # Install dependencies if node_modules doesn't exist
    if [ ! -d "node_modules" ]; then
        log "Installing PharmaStock dependencies..."
        
        # Create symlink to RAM-based node_modules directory
        if [ ! -L "node_modules" ]; then
            ln -sf /opt/cache/node_modules node_modules
            log "Created symlink to RAM-based node_modules directory"
        fi
        
        # Check if we have cached dependencies
        PACKAGE_HASH=$(md5sum package.json 2>/dev/null | cut -d' ' -f1 || echo "none")
        CACHE_HASH_FILE="$CACHE_DIR/package-hash.txt"
        CACHED_HASH=""
        
        if [ -f "$CACHE_HASH_FILE" ]; then
            CACHED_HASH=$(cat "$CACHE_HASH_FILE")
        fi
        
        if [ "$PACKAGE_HASH" != "$CACHED_HASH" ] || [ ! -d "/opt/node_modules" ]; then
            log "Package dependencies changed or missing, installing..."
            
            # Install with optimized settings for RAM and minimal writes
            npm install \
                --cache /tmp/.npm \
                --prefer-offline \
                --no-audit \
                --no-fund \
                --no-optional \
                --production \
                --silent
            
            # Save package hash for future reference
            echo "$PACKAGE_HASH" > "$CACHE_HASH_FILE"
            log "Dependencies installed and cached"
        else
            log "Dependencies are up to date, using cached version"
        fi
    fi
    
    # Start backend service (port 3000)
    log "Starting PharmaStock backend on port 3000..."
    if command -v pm2 &> /dev/null; then
        # Use PM2 if available
        pm2 start "npm run dev:backend" --name "pharmastock-backend" --cwd "$APP_DIR"
    else
        # Install PM2 if not available
        log "Installing PM2 process manager..."
        npm install -g pm2
        pm2 start "npm run dev:backend" --name "pharmastock-backend" --cwd "$APP_DIR"
    fi
    
    # Start frontend service (port 3001)
    log "Starting PharmaStock frontend on port 3001..."
    pm2 start "npm run dev:frontend" --name "pharmastock-frontend" --cwd "$APP_DIR"
    
    # Save PM2 configuration
    pm2 save
    pm2 startup
    
    # Check if services are running
    if pm2 list | grep -q "pharmastock-backend.*online" && pm2 list | grep -q "pharmastock-frontend.*online"; then
        log "PharmaStock services started successfully"
        log "Backend: http://localhost:3000"
        log "Frontend: http://localhost:3001"
        log "Pharmacy: http://new-sight.local/pharmacy"
    else
        log "WARNING: Some PharmaStock services may not have started properly"
        pm2 list
    fi
}

# Main execution
main() {
    log "=== Pi Setup Script Started ==="
    
    # Check if running as root
    check_root
    
    # Step 1: Configure additional tmpfs mounts for write reduction
    configure_tmpfs_mounts
    
    # Step 2: Configure zram for RAM-based swap
    configure_zram_swap
    
    # Step 3: Configure journald
    configure_journald
    
    # Step 4: Install and configure log2ram
    install_log2ram
    
    # Step 5: Install and configure nginx
    install_nginx
    
    # Step 6: Configure nginx
    configure_nginx
    
    # Step 7: Setup and start PharmaStock application
    setup_pharmastock
    
    log "=== Pi Setup Script Completed Successfully ==="
}

# Run main function
main "$@"
