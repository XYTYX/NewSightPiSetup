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
    
    # # Run setup-pi.sh if it exists
    # if [ -f "setup-pi.sh" ]; then
    #     log "Running setup-pi.sh script..."
    #     chmod +x setup-pi.sh
    #     ./setup-pi.sh
    #     log "PharmaStock setup-pi.sh completed successfully"
    # else
    #     log "WARNING: setup-pi.sh not found in PharmaStock repository"
    # fi

    # Test deployment TODO:delete
    if [ -f "test-deploy.sh" ]; then
        log "Running test-deploy.sh script..."
        chmod +x test-deploy.sh
        sudo ./test-deploy.sh production setup
        log "PharmaStock test-deploy.sh completed successfully"
    else
        log "WARNING: test-deploy.sh not found in PharmaStock repository"
    fi
    
    # Start PharmaStock services
    #TODO: delete
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
        npm install
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
    
    # Step 1: Configure journald
    configure_journald
    
    # Step 2: Install and configure log2ram
    install_log2ram
    
    # Step 3: Install and configure nginx
    install_nginx
    
    # Step 4: Configure nginx
    configure_nginx
    
    # Step 5: Setup and start PharmaStock application
    setup_pharmastock
    
    log "=== Pi Setup Script Completed Successfully ==="
}

# Run main function
main "$@"
