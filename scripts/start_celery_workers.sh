#!/bin/bash

# start_celery_workers.sh
# Launch Celery workers dynamically per Django project based on celery_workers.yml
# Usage:
#   ./start_celery_workers.sh              → Start all projects
#   ./start_celery_workers.sh <project>    → Start one project by directory name
# Features:
#   - Dynamically finds all /var/www/sites/*/current
#   - Extracts real Celery module from celery_workers.yml
#   - Stops previous Celery workers before starting new ones
#   - Logs are saved to /var/log/celery/<worker>.log
#   - Workers run in background using nohup

set -e  # Exit script if any command fails

BASE_DIR="/var/www/sites"
LOG_DIR="/var/log/celery"

TARGET_PROJECT=$1  # Optional argument: specific project folder

# Logging helpers
log()   { echo "$(date +"%F %T") [INFO] - $*"; }
warn()  { echo "$(date +"%F %T") [WARNING] - $*" >&2; }
err()   { echo "$(date +"%F %T") [ERROR] - $*" >&2; }

# Loop through all matching project paths under /var/www/sites/*/current
for path in "$BASE_DIR"/*/current; do
    [ -d "$path" ] || continue

    # Extract folder name from /var/www/sites/<folder>/current
    folder_name=$(basename "$(dirname "$path")")

    # Skip if specific project is requested and this one doesn't match
    if [ -n "$TARGET_PROJECT" ] && [ "$folder_name" != "$TARGET_PROJECT" ]; then
        continue
    fi

    venv_path="$path/venv/bin/activate"
    config_file="$path/celery_workers.yml"

    if [ ! -f "$venv_path" ]; then
        warn "No virtualenv in $venv_path, skipping $folder_name"
        continue
    fi

    if [ ! -f "$config_file" ]; then
        warn "No celery_workers.yml found for $folder_name, skipping"
        continue
    fi

    # Extract the actual Celery module from the YAML
    module=$(yq -r ".module" "$config_file")
    if [ -z "$module" ] || [ "$module" == "null" ]; then
        err "Missing 'module' in $config_file for $folder_name, skipping"
        continue
    fi

    log "Stopping existing Celery workers for module '$module'..."
    sudo pkill -f "celery -A $module" || true
    sleep 1

    log "Activating environment and launching workers for $folder_name"
    source "$venv_path"
    cd "$path" || continue

    # Read number of workers defined
    worker_count=$(yq -r '.workers | length' "$config_file")

    for i in $(seq 0 $((worker_count - 1))); do
        queue=$(yq -r ".workers[$i].queue // empty" "$config_file")
        concurrency=$(yq -r ".workers[$i].concurrency" "$config_file")
        worker_name=$(yq -r ".workers[$i].name" "$config_file")

        full_name="${worker_name}.$(hostname)"
        log_file="${LOG_DIR}/${worker_name}.log"

        base_path="/var/www/sites/$folder_name"

        # Ruta completa al ejecutable celery
        celery_bin="$base_path/current/venv/bin/celery"

        # Build command dynamically usando la ruta completa
        cmd="$celery_bin -A \"$module\" worker"
        [ -n "$queue" ] && cmd="$cmd -Q \"$queue\""
        cmd="$cmd --concurrency=$concurrency -n \"$full_name\" -l INFO"

        log "Starting worker: $full_name → queue='${queue:-celery}', concurrency=$concurrency"
        sudo bash -c "nohup $cmd > \"$log_file\" 2>&1 &"
    done

    deactivate
done

log "All requested Celery workers launched successfully."
