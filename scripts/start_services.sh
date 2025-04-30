#!/bin/bash

# restart_services.sh
# Script to start or restart Gunicorn services for Django projects
# Can be executed for all projects in /var/www/sites/* or for a specific project

set -e

# Function for logging messages
log_info() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] - $1"
}

log_error() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] - $1" >&2
}

log_warning() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [WARNING] -  $1" >&2
}

# Function to restart a Gunicorn service
restart_gunicorn() {
    local base_path="$1"
    local site=$(basename "$base_path")

    log_info "Processing site: $site"

    # Define paths
    local current_path="$base_path/current"
    local venv_path="venv"  # Default, can be modified as needed

    # Verify if current directory exists
    if [ ! -d "$current_path" ]; then
        log_error "Directory '$current_path' not found for site $site"
        return 1
    fi

    # Path to Gunicorn executable
    local gunicorn_bin="$current_path/$venv_path/bin/gunicorn"

    # Define Unix socket for Gunicorn
    local socket_path="/run/gunicorn/$site.sock"

    # Define log file paths
    local access_log="/var/log/gunicorn/$site-access.log"
    local error_log="/var/log/gunicorn/$site-error.log"

    # Ensure directories for logs and sockets exist
    if [ ! -d "/var/log/gunicorn" ]; then
        log_error "Directory '/var/log/gunicorn' does not exist. Please create it with proper permissions."
        return 1
    fi

    if [ ! -d "/run/gunicorn" ]; then
        log_error "Directory '/run/gunicorn' does not exist. Please create it with proper permissions."
        return 1
    fi

    # Search for wsgi.py file
    local wsgi_path=$(find "$current_path/" -maxdepth 2 -name wsgi.py | head -n 1)

    # Verify if wsgi.py was found
    if [ -z "$wsgi_path" ]; then
        log_error "Could not find wsgi.py file in $current_path/"
        return 1
    fi

    # Extract project name
    local project_dir=$(dirname "$wsgi_path")
    local project_name=$(basename "$project_dir")

    # Log where wsgi.py was found
    log_info "Found wsgi.py in $wsgi_path, project: $project_name"
    log_info "Running Gunicorn for $project_name in background..."

    # Kill previous Gunicorn processes for this site
    local kill_cmd="ps -eo pid,cmd | grep gunicorn | grep '$socket_path' | awk '{print \$1}' | xargs -r kill"
    log_info "Stopping previous Gunicorn processes for $site..."
    eval "$kill_cmd" || true

    # Execute Gunicorn directly (without temporary script)
    log_info "Starting Gunicorn directly for $site"

    # Use nohup to run in background and redirect output to log files
    cd "$project_dir"
    export PYTHONPATH="$current_path"

    # Launch Gunicorn directly in background
    nohup "$gunicorn_bin" --workers=3 \
    --bind=unix:"$socket_path" \
    "$project_name".wsgi:application \
    --access-logfile "$access_log" \
    --error-logfile "$error_log" \
    --log-level=debug \
    >> "/tmp/gunicorn_direct_$site.log" 2>&1 &

    # Save the PID for verification
    local GUNICORN_PID=$!
    log_info "Launched Gunicorn with PID: $GUNICORN_PID"

    # Give it a moment to start
    sleep 2

    # Verify if the process is still running
    if kill -0 $GUNICORN_PID 2>/dev/null; then
        log_info "Verified Gunicorn is running for $site with PID $GUNICORN_PID"
    else
        log_warning "Could not verify if Gunicorn started for $site. Check logs at /tmp/gunicorn_direct_$site.log"
    fi
}

# Check if we should keep alive for Supervisor
if [ "$1" = "supervisor" ]; then
    log_info "Executing in supervisor mode"

    # Process all sites
    for site_path in /var/www/sites/*; do
        if [ -d "$site_path" ]; then
            restart_gunicorn "$site_path" || true
        fi
    done

    log_info "Services started. Keeping process alive for Supervisor."

    # Keep the script running indefinitely for Supervisor
    counter=0
    while true; do
        counter=$((counter + 1))
        if (( counter % 60 == 0 )); then
            # Every 60 cycles (roughly every hour), check if processes are still running
            log_info "Periodic check - Cycle $counter"
            for site_path in /var/www/sites/*; do
                if [ -d "$site_path" ] && [ -d "$site_path/current" ]; then
                    site=$(basename "$site_path")
                    socket_path="/run/gunicorn/$site.sock"

                    # Check if socket exists
                    if [ ! -S "$socket_path" ]; then
                        log_warning "Socket missing for $site, restarting..."
                        restart_gunicorn "$site_path"
                    fi
                fi
            done
        fi
        sleep 60  # Sleep for a minute
    done
else
    # Standard one-time execution mode
    # Check if a specific site was provided
    if [ $# -eq 1 ]; then
        # Check if the directory exists
        if [ -d "/var/www/sites/$1" ]; then
            restart_gunicorn "/var/www/sites/$1"
        else
            log_error "Specified site '/var/www/sites/$1' does not exist."
            exit 1
        fi
    else
        # Process all sites
        for site_path in /var/www/sites/*; do
            if [ -d "$site_path" ]; then
                restart_gunicorn "$site_path" || true
            fi
        done
    fi

    log_info "Service restart process completed."
fi