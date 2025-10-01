#!/bin/bash

# nginx-setup.sh
# Setup nginx reverse proxy for new-sight.local/pharmacy -> 127.0.0.1:3001

set -e  # Exit on any error

# Configuration
HOSTNAME="new-sight.local"
APP_PORT="3001"
APP_PATH="/pharmacy"
NGINX_CONFIG_DIR="/etc/nginx"
SITES_AVAILABLE_DIR="${NGINX_CONFIG_DIR}/sites-available"
SITES_ENABLED_DIR="${NGINX_CONFIG_DIR}/sites-enabled"
CONFIG_FILE="new-sight"

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to install nginx if not present
install_nginx() {
    log "Checking for nginx installation..."
    
    if command -v nginx >/dev/null 2>&1; then
        log "nginx is already installed"
        return 0
    fi
    
    log "Installing nginx..."
    
    # Update package list
    apt-get update
    
    # Install nginx
    apt-get install -y nginx
    
    log "nginx installed successfully"
}

# Function to create nginx configuration
create_nginx_config() {
    log "Creating nginx configuration for ${HOSTNAME}${APP_PATH} -> 127.0.0.1:${APP_PORT}..."
    
    # Create the configuration file
    cat > "${SITES_AVAILABLE_DIR}/${CONFIG_FILE}" << EOF
server {
    listen 80;
    server_name ${HOSTNAME};
    
    # Main application proxy
    location ${APP_PATH}/ {
        proxy_pass http://127.0.0.1:${APP_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Handle WebSocket connections if needed
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Redirect root to pharmacy path
    location = / {
        return 301 ${APP_PATH}/;
    }
    
    # Default location for other paths
    location / {
        return 404;
    }
}
EOF
    
    log "nginx configuration created at ${SITES_AVAILABLE_DIR}/${CONFIG_FILE}"
}

# Function to enable the site
enable_site() {
    log "Enabling nginx site..."
    
    # Remove default site if it exists
    if [ -L "${SITES_ENABLED_DIR}/default" ]; then
        log "Removing default nginx site..."
        rm "${SITES_ENABLED_DIR}/default"
    fi
    
    # Create symbolic link to enable the site
    if [ ! -L "${SITES_ENABLED_DIR}/${CONFIG_FILE}" ]; then
        ln -s "${SITES_AVAILABLE_DIR}/${CONFIG_FILE}" "${SITES_ENABLED_DIR}/${CONFIG_FILE}"
        log "Site enabled successfully"
    else
        log "Site is already enabled"
    fi
}

# Function to configure hostname
configure_hostname() {
    log "Configuring hostname ${HOSTNAME}..."
    
    # Add hostname to /etc/hosts if not already present
    if ! grep -q "${HOSTNAME}" /etc/hosts; then
        echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
        log "Added ${HOSTNAME} to /etc/hosts"
    else
        log "${HOSTNAME} already exists in /etc/hosts"
    fi
}

# Function to test nginx configuration
test_nginx_config() {
    log "Testing nginx configuration..."
    
    if nginx -t; then
        log "nginx configuration test passed"
        return 0
    else
        log "ERROR: nginx configuration test failed"
        return 1
    fi
}

# Function to start and enable nginx
start_nginx() {
    log "Starting and enabling nginx service..."
    
    # Enable nginx to start on boot
    systemctl enable nginx
    
    # Start nginx service
    systemctl start nginx
    
    # Check if nginx is running
    if systemctl is-active --quiet nginx; then
        log "nginx service started successfully"
    else
        log "ERROR: Failed to start nginx service"
        systemctl status nginx
        return 1
    fi
}

# Function to reload nginx configuration
reload_nginx() {
    log "Reloading nginx configuration..."
    
    if systemctl reload nginx; then
        log "nginx configuration reloaded successfully"
    else
        log "ERROR: Failed to reload nginx configuration"
        return 1
    fi
}

# Main execution
main() {
    log "=== Nginx Reverse Proxy Setup Started ==="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # 1. Install nginx
    install_nginx
    
    # 2. Configure hostname
    configure_hostname
    
    # 3. Create nginx configuration
    create_nginx_config
    
    # 4. Enable the site
    enable_site
    
    # 5. Test nginx configuration
    if ! test_nginx_config; then
        log "ERROR: nginx configuration test failed, aborting"
        exit 1
    fi
    
    # 6. Start nginx service
    start_nginx
    
    # 7. Reload configuration to ensure it's active
    reload_nginx
    
    log "=== Nginx Reverse Proxy Setup Completed Successfully ==="
    log ""
    log "Configuration details:"
    log "  - Hostname: ${HOSTNAME}"
    log "  - Application path: ${APP_PATH}"
    log "  - Backend: 127.0.0.1:${APP_PORT}"
    log "  - Config file: ${SITES_AVAILABLE_DIR}/${CONFIG_FILE}"
    log ""
    log "Access your application at: http://${HOSTNAME}${APP_PATH}/"
    log ""
    log "Service management commands:"
    log "  - Check nginx status: systemctl status nginx"
    log "  - View nginx logs: journalctl -u nginx"
    log "  - Test configuration: nginx -t"
    log "  - Reload configuration: systemctl reload nginx"
    log "  - Restart nginx: systemctl restart nginx"
}

# Run main function
main "$@"
