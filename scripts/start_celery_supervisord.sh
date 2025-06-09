#!/bin/bash

# Script para generar configuración de supervisord para Celery
# Basado en tu script original de celery_workers
# Uso: ./start_celery_supervisord.sh [nombre_sitio_opcional]

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

# Additional variables for supervisord
SUPERVISORD_DIR=${SUPERVISORD_DIR:-/etc/supervisor/conf.d}
BASE_SITES_DIR=${BASE_SITES_DIR:-/var/www/sites}
LOG_DIR="/var/log/celery"
APP_USER=${APP_USER:-admin}

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

if [ ! -d "$LOG_DIR" ]; then
    log_info "Creating celery logs directory: $LOG_DIR"
    mkdir -p $LOG_DIR
else
    log_info "✓ Celery logs directory exists: $LOG_DIR"
fi

# Function to configure celery workers of a specific site
configure_celery_site() {
    local site_path="$1"
    local site_name=$(basename "$site_path")

    log_info "Processing site: $site_name"

    # Build paths like in your original code
    local current_path="$site_path/current"
    local venv_path="venv"
    local config_file="$current_path/celery_workers.yml"

    log_info "Base path: $site_path"
    log_info "Current path: $current_path"
    log_info "Config file: $config_file"

    # Verify if the current directory exists
    if [ ! -d "$current_path" ]; then
        log_error "Directory '$current_path' not found for site $site_name"
        return 1
    fi

    # Verify if the configuration file exists
    if [ ! -f "$config_file" ]; then
        log_warning "No celery_workers.yml found for $site_name, skipping"
        return 1
    fi

    # Path to Celery executable (como en tu código original)
    local celery_bin="$current_path/$venv_path/bin/celery"

    # Verify that the celery binary exists
    if [ ! -f "$celery_bin" ]; then
        log_error "Celery binary not found at '$celery_bin' for site $site_name"
        return 1
    fi

    # Extract the Celery module from the YAML
    local module=$(yq -r ".module" "$config_file")
    if [ -z "$module" ] || [ "$module" == "null" ]; then
        log_error "Missing 'module' in $config_file for $site_name"
        return 1
    fi

    log_info "Celery module: $module"
    log_info "Celery binary: $celery_bin"

    # Read number of workers defined
    local worker_count=$(yq -r '.workers | length' "$config_file")
    log_info "Worker count: $worker_count"

    # Process each worker
    for i in $(seq 0 $((worker_count - 1))); do
        local queue=$(yq -r ".workers[$i].queue // empty" "$config_file")
        local concurrency=$(yq -r ".workers[$i].concurrency" "$config_file")
        local worker_name=$(yq -r ".workers[$i].name" "$config_file")

        local full_name="${worker_name}.%%h"
        local log_file="${LOG_DIR}/${worker_name}.log"

        log_info "=== Configuring Celery Worker: $worker_name ==="
        log_info "Queue: ${queue:-celery}"
        log_info "Concurrency: $concurrency"
        log_info "Full name: $full_name"
        log_info "Log file: $log_file"

        # Build celery command
        local cmd="$celery_bin -A $module worker"
        [ -n "$queue" ] && cmd="$cmd -Q $queue"
        cmd="$cmd --concurrency=$concurrency -n $full_name -l INFO --without-gossip --without-mingle --without-heartbeat"

        log_info "Command: $cmd"

        # Generate Celery Worker configuration for supervisord
        local config_file_path="/tmp/django-celery-$site_name-$worker_name.conf"
        local final_config_file="$SUPERVISORD_DIR/django-celery-$site_name-$worker_name.conf"

        cat > "$config_file_path" << EOF
[program:django-celery-$site_name-$worker_name]
command=$cmd
directory=$current_path
user=$APP_USER
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/celery-$site_name-$worker_name.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
environment=PATH="$current_path/$venv_path/bin:/usr/local/bin:/usr/bin:/bin",PYTHONPATH="$current_path"
priority=920
startsecs=10
startretries=3
stopwaitsecs=30
killasgroup=true
stopasgroup=true
EOF

        # Move the temporary file to the final directory with sudo
        log_info "Moving configuration to $final_config_file..."
        if sudo mv "$config_file_path" "$final_config_file"; then
            log_info "✓ Configuration created: $final_config_file"
        else
            log_error "Error moving configuration to $final_config_file"
            return 1
        fi
    done
}

# Verify parameters and process sites
if [ -n "$1" ]; then
    # A specific site was specified
    SITE_NAME=$1
    site_path="$BASE_SITES_DIR/$SITE_NAME"

    log_info "Site specified: $SITE_NAME"

    if [ -d "$site_path" ]; then
        configure_celery_site "$site_path"
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

    # Iterate over each site
    for site_path in $BASE_SITES_DIR/*; do
        if [ -d "$site_path" ]; then
            configure_celery_site "$site_path" || true  # Continue even if one fails
        fi
    done
fi

# Si supervisord está corriendo, aplicar cambios
if command -v supervisorctl >/dev/null 2>&1 && pgrep supervisord >/dev/null; then
    log_info "Applying configuration to supervisord..."
    if sudo supervisorctl reread && sudo supervisorctl update; then
        log_info "Changes applied successfully"
        log_info "Services status:"
        sudo supervisorctl status | grep django-celery
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
log_info "Logs available in: /var/log/supervisor/ and $LOG_DIR/"