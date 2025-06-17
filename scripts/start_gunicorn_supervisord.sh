#!/bin/bash

# Script adapted to generate supervisord configuration for Gunicorn
# Based on your original gunicorn script
# Usage: $0 [optional_site_name]

set -e

# Function for logging messages
log_info() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] - $1"
}

log_error() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] - $1" >&2
}

log_warning() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [WARNING] - $1" >&2
}

# Default variables (same as your original script)
WORKERS=${WORKERS:-7}
TIMEOUT=${TIMEOUT:-300}
KEEP_ALIVE=${KEEP_ALIVE:-5}
WORKER_CONNECTIONS=${WORKER_CONNECTIONS:-1000}
MAX_REQUESTS=${MAX_REQUESTS:-2000}
MAX_REQUESTS_JITTER=${MAX_REQUESTS_JITTER:-200}

# Additional variables for supervisord
SUPERVISORD_DIR=${SUPERVISORD_DIR:-/etc/supervisor/conf.d}
# Base directory of sites
BASE_SITES_DIR=${BASE_SITES_DIR:-/var/www/sites}
APP_USER=${APP_USER:-admin}
LOG_LEVEL=${LOG_LEVEL:-info}

# Validate that the supervisord directories exist
if [ ! -d "$SUPERVISORD_DIR" ]; then
    log_info "Creating supervisord configuration directory: $SUPERVISORD_DIR"
    mkdir -p $SUPERVISORD_DIR
else
    log_info "✓ Supervisord configuration directory exists: $SUPERVISORD_DIR"
fi

if [ ! -d "/var/log/supervisor" ]; then
    log_info "Creating supervisord logs directory: /var/log/supervisor"
    mkdir -p /var/log/supervisor
else
    log_info "✓ Supervisord logs directory exists: /var/log/supervisor"
fi

if [ ! -d "/var/log/gunicorn" ]; then
    log_info "Creating gunicorn logs directory: /var/log/gunicorn"
    mkdir -p /var/log/gunicorn
else
    log_info "✓ Gunicorn logs directory exists: /var/log/gunicorn"
fi

# Function to configure a specific site
configure_site() {
    local site_path="$1"
    local site_name=$(basename "$site_path")

    log_info "Processing site: $site_name"

    # Build paths like in your original code
    local current_path="$site_path/current"
    local venv_path="venv"  # Default, can be modified as needed

    # Path to Gunicorn executable (como en tu código original)
    local gunicorn_bin="$current_path/$venv_path/bin/gunicorn"

    # Define Unix socket for Gunicorn (like in your original code)
    local socket_path="/run/gunicorn/$site_name.sock"

    log_info "Base path: $site_path"
    log_info "Current path: $current_path"
    log_info "Gunicorn binary: $gunicorn_bin"
    log_info "Socket path: $socket_path"

    # Verify if the current directory exists
    if [ ! -d "$current_path" ]; then
        log_error "Directory '$current_path' not found for site $site_name"
        return 1
    fi

    # Verify if the gunicorn binary exists
    if [ ! -f "$gunicorn_bin" ]; then
        log_error "Gunicorn binary not found at '$gunicorn_bin' for site $site_name"
        return 1
    fi

    # Ensure directories for logs and sockets exist (like in your original code)
    if [ ! -d "/run/gunicorn" ]; then
        log_error "Directory '/run/gunicorn' does not exist. Please create it with proper permissions."
        return 1
    fi

    # Detect Django project automatically
    log_info "Detecting Django project for $site_name..."

    # Search wsgi.py in the current directory (like in your original code)
    local wsgi_path=$(find "$current_path/" -maxdepth 2 -name wsgi.py | head -n 1)

    if [ -z "$wsgi_path" ]; then
        log_error "Could not find wsgi.py file in $current_path/ for site $site_name"
        return 1
    fi

    # Extract project name
    local project_dir=$(dirname "$wsgi_path")
    local django_project=$(basename "$project_dir")

    log_info "Found wsgi.py in $wsgi_path, project: $django_project"

    log_info "=== Configurando Gunicorn para $site_name ==="
    log_info "Workers: $WORKERS"
    log_info "Timeout: $TIMEOUT"
    log_info "Keep-alive: $KEEP_ALIVE"
    log_info "Worker connections: $WORKER_CONNECTIONS"
    log_info "Max requests: $MAX_REQUESTS"
    log_info "Max requests jitter: $MAX_REQUESTS_JITTER"
    log_info "Socket: $socket_path"
    log_info "Proyecto Django: $django_project"
    log_info "Directorio de trabajo: $project_dir"

    # Configure log files using your structure (with the site name)
    local access_log="/var/log/gunicorn/$site_name-access.log"
    local error_log="/var/log/gunicorn/$site_name-error.log"

    log_info "Access log: $access_log"
    log_info "Error log: $error_log"

    # Generate Gunicorn configuration for supervisord (one file per site)
    local config_file="/tmp/django-gunicorn-$site_name.conf"
    local final_config_file="$SUPERVISORD_DIR/django-gunicorn-$site_name.conf"

    cat > "$config_file" << EOF
[program:django-gunicorn-$site_name]
command=$gunicorn_bin --bind unix:$socket_path --workers $WORKERS --timeout $TIMEOUT --keep-alive $KEEP_ALIVE --worker-connections $WORKER_CONNECTIONS --max-requests $MAX_REQUESTS --max-requests-jitter $MAX_REQUESTS_JITTER --log-level $LOG_LEVEL --access-logfile $access_log --error-logfile $error_log $django_project.wsgi:application
directory=$project_dir
user=$APP_USER
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/gunicorn-$site_name.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile=/var/log/supervisor/gunicorn-$site_name-error.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10
environment=HOME="/home/$APP_USER",PATH="$current_path/$venv_path/bin:/usr/local/bin:/usr/bin:/bin",PYTHONPATH="$current_path"
priority=900
startsecs=10
startretries=3
stopwaitsecs=10
EOF

    # Move the temporary file to the final directory with sudo
    log_info "Moving configuration to $final_config_file..."
    if sudo mv "$config_file" "$final_config_file"; then
        log_info "✓ Configuration created: $final_config_file"
    else
        log_error "Error moving configuration to $final_config_file"
        return 1
    fi
}

# Verify parameters and process sites
if [ -n "$1" ]; then
    # A specific site was specified
    SITE_NAME=$1
    site_path="$BASE_SITES_DIR/$SITE_NAME"

    log_info "Site specified: $SITE_NAME"

    if [ -d "$site_path" ]; then
        configure_site "$site_path"
    else
        log_error "Specified site '$site_path' does not exist."
        exit 1
    fi
else
    # Process all sites (like in your original code)
    log_info "Processing all sites in $BASE_SITES_DIR/*"

    # Verify that the base directory exists
    if [ ! -d "$BASE_SITES_DIR" ]; then
        log_error "Directory '$BASE_SITES_DIR' does not exist."
        exit 1
    fi

    # Iterar cada sitio
    for site_path in $BASE_SITES_DIR/*; do
        if [ -d "$site_path" ]; then
            configure_site "$site_path" || true  # Continúa aunque falle uno
        fi
    done
fi

# If supervisord is running, apply changes
if command -v supervisorctl >/dev/null 2>&1 && pgrep supervisord >/dev/null; then
    log_info "Applying configuration to supervisord..."
    if sudo supervisorctl reread && sudo supervisorctl update; then
        log_info "Changes applied successfully"
        log_info "Services status:"
        sudo supervisorctl status | grep django-gunicorn
    else
        log_error "Error applying changes to supervisord"
        log_info "Apply manually with:"
        log_info "sudo supervisorctl reread && sudo supervisorctl update"
    fi
else
    log_info "To apply the configuration when supervisord is running:"
    log_info "sudo supervisorctl reread && sudo supervisorctl update"
fi

log_info "=== Process completed ==="
log_info "Configurations created in: $SUPERVISORD_DIR/"
log_info "Logs available in: /var/log/supervisor/ and /var/log/gunicorn/"