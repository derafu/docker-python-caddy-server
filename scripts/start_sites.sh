#!/bin/bash

TARGET_SITE="$1"

echo "Searching for projects in /var/www/sites"

# Create logs folder if it doesn't exist
mkdir -p /var/log/gunicorn

for site in /var/www/sites/*; do
  SITENAME=$(basename "$site")

  # If an argument was passed and doesn't match, skip
  if [ -n "$TARGET_SITE" ] && [ "$SITENAME" != "$TARGET_SITE" ]; then
    continue
  fi

  if [ -d "$site" ]; then
    echo "Checking: $site"
    wsgi_path=$(find "$site" -maxdepth 2 -type f -name wsgi.py | head -n 1)

    if [ -n "$wsgi_path" ]; then
      PROJECT_DIR=$(dirname "$wsgi_path")
      PROJECT_NAME=$(basename "$PROJECT_DIR")
      VENV_PATH="$site/venv"
      GUNICORN_BIN="$VENV_PATH/bin/gunicorn"
      PYTHON_BIN="$VENV_PATH/bin/python"
      REQUIREMENTS="$site/requirements.txt"

      echo "Starting preparation for: $PROJECT_NAME"
      echo "wsgi.py located at: $wsgi_path"
      echo "Project: $PROJECT_DIR"
      echo "Virtualenv: $VENV_PATH"

      (
        cd "$PROJECT_DIR"
        export PYTHONPATH="$site"

        # Create virtual environment if it doesn't exist
        if [ ! -d "$VENV_PATH" ]; then
          echo "Creating virtual environment..."
          python3 -m venv "$VENV_PATH"
        fi

        # Install requirements if they exist
        if [ -f "$REQUIREMENTS" ]; then
          echo "Installing dependencies..."
          "$VENV_PATH/bin/pip" install --upgrade pip
          "$VENV_PATH/bin/pip" install -r "$REQUIREMENTS"
        fi

        # Apply migrations
        echo "Applying migrations..."
        "$PYTHON_BIN" "$site/manage.py" migrate --noinput

        # Seed database
        echo "Seeding database..."
        "$PYTHON_BIN" "$site/manage.py" db_seed

        # Collect static files
        echo "Collecting static files..."
        "$PYTHON_BIN" "$site/manage.py" collectstatic --noinput

        # Define logs per project
        ACCESS_LOG="/var/log/gunicorn/${SITENAME}-access.log"
        ERROR_LOG="/var/log/gunicorn/${SITENAME}-error.log"

        # Run Gunicorn with redirected logs
        echo "Running Gunicorn: $GUNICORN_BIN"
        "$GUNICORN_BIN" --workers=3 \
          --bind=unix:/run/gunicorn/${SITENAME}.sock \
          "$PROJECT_NAME.wsgi:application" \
          --access-logfile "$ACCESS_LOG" \
          --error-logfile "$ERROR_LOG" \
          --log-level=info
      ) &
    else
      echo "No wsgi.py found in $site"
    fi
  fi
done

wait
