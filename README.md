# Derafu Sites Server - Docker with Python and Caddy for Fabric

![GitHub last commit](https://img.shields.io/github/last-commit/derafu/docker-python-caddy-server/main)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/derafu/docker-python-caddy-server)
![GitHub Issues](https://img.shields.io/github/issues-raw/derafu/docker-python-caddy-server)

A modern Docker setup for hosting Python websites with Caddy web server and SSH access for Fabric deployments.

## Features

- **Python 3.13.1**: Supported Python version with common extensions.
- **Caddy**: Modern web server with automatic HTTPS.
- **SSH Access**: For automated deployments with Fabric.
- **Automatic Site Discovery**: Just add your site folder and it works.
- **Development Domains**: Test with .local domains that map to production folders.
- **Automatic WWW Redirection**: For second-level domains (e.g., example.com → www.example.com).
- **Auto-HTTPS**: Certificates are automatically generated on-demand.
- **Environment Separation**: Development and production environments managed through Docker Compose override.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed on your system.
- SSH key for deployment access.

### Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/derafu/docker-python-caddy-server.git
   cd docker-python-caddy-server
   ```

2. Add your SSH public key to `config/ssh/authorized_keys` for admin, and default deployment, access:
   ```bash
   cat ~/.ssh/id_rsa.pub > config/ssh/authorized_keys
   ```

3. Build and start the container:
   ```bash
   docker-compose up -d
   ```
   The `-d` parameter runs it in detached mode (background).

### Verification

Check that the container is running:

```bash
docker-compose ps
```

View container logs:

```bash
docker-compose logs -f
```

The `-f` parameter allows you to follow logs in real-time.

### Testing Your First Site

1. Create the site directory structure:
   ```bash
   mkdir -p sites/www.example.com/
   cd sites/www.example.com/
   ```

2. Create project Django
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install django
   django-admin startproject example .
   ```

3. Run a single site manually
   ```bash
   /scripts/start_sites.sh www.example.com
   ```
   Note: If no site is specified, the script will start all available sites under /var/www/sites.


4. Access the site at:
   - Production mode: https://www.example.com (requires DNS configuration).
   - Development mode: https://www.example.com.local:8443 (requires local hosts entry).

For local development, add to your `/etc/hosts` file:
```
127.0.0.1 www.example.com.local
```

## Directory Structure

```
docker-python-caddy-server/
├── Dockerfile                  # Python + Caddy server base image definition
├── docker-compose.yml          # Production Docker services and volumes
├── .env                        # Environment variables for docker-compose
├── LICENSE                     # Project license
├── README.md                   # Main project documentation
Configuration
├── config/
│   ├── bash/
│   │   └── bashrc              # Shell prompt / history tweaks for container user
│   ├── caddy/
│   │   └── Caddyfile           # Caddy reverse proxy rules (HTTPS, domains, routing)
│   ├── cron/
│   │   └── logrotate           # Cron job for rotating logs periodically
│   ├── logrotate/
│   │   ├── caddy               # Logrotate rules for Caddy
│   │   └── gunicorn            # Logrotate rules for Gunicorn
│   ├── ssh/
│   │   ├── authorized_keys     # Public keys for SSH login (e.g., deploy access)
│   │   └── sshd_config         # SSH server settings (OpenSSH)
│   └── supervisor/
│       └── supervisord.conf    # Supervisor config to manage processes (Caddy, Gunicorn, etc.)
Development
├── sites/                      # Django projects, one per domain
│   └── www.example.com/        # Project folder for www.example.com
Helper Scripts
├── scripts/
│   └── start_sites.sh          # Auto-detect and launch Gunicorn for each site under /sites
Documentation
├── docs/
│   ├── docker.md               # Notes and recommendations for Docker usage
```

## Development vs Production Environment

This project uses Docker Compose's override functionality to separate development and production configurations:

### Production Environment

The base `docker-compose.yml` contains the minimal configuration needed for production deployment. It:

- Sets up required environment variables.
- Defines essential ports (HTTP, HTTPS, SSH).
- Doesn't mount external volumes.

### Development Environment

The `docker-compose.override.yml` file adds development-specific settings:

- Adds additional development ports (e.g., management interface).
- Mounts local volumes for easy site development.

### Usage:

- **Development**: Docker Compose automatically merges both files:
  ```bash
  docker-compose up -d
  ```

- **Production**: Use only the base configuration:
  ```bash
  docker-compose -f docker-compose.yml up -d
  ```

## Access and Management

### SSH Access

Connect to the container via SSH:

```bash
ssh admin@localhost -p 2222
```

### Direct Container Access

Access the container shell:

```bash
docker exec -it derafu-sites-server-python-caddy bash
```

### Restarting Services

Restart Caddy web server:

```bash
docker exec -it derafu-sites-server-python-caddy supervisorctl restart caddy
```

### Stopping the Container

```bash
docker-compose down
```

### Rebuilding After Configuration Changes

Rebuild for development:

```bash
docker-compose build --no-cache
docker-compose up -d
```

Rebuild for production:

```bash
docker-compose -f docker-compose.yml build --no-cache
docker-compose -f docker-compose.yml up -d
```

## Adding New Sites

1. Create the site directory structure:
   ```bash
   mkdir -p sites/www.newsite.com/
   cd sites/www.newsite.com/
   ```

2. Create project Django
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install django
   django-admin startproject newsite .
   ```
   NOTE: Es importante que el archivo requirements.txt contenga  la dependencia gunicorn (Ejemplo gunicorn==23.0.0)

3. No server restart required! Caddy automatically detects new sites.

4. For local development, add to your hosts file:
   ```
   127.0.0.1 www.newsite.com.local
   ```

## Environment Variables

Customize behavior through environment variables:

| Variable                     | Description                       | Default             |
|------------------------------|-----------------------------------|---------------------|
| `SERVER_NAME`                | Name for the docker container     | derafu-sites-server |
| `CADDY_DEBUG`                | Enable debug mode with `debug`    | (empty)             |
| `CADDY_EMAIL`                | Email for Let's Encrypt           | admin@example.com   |
| `CADDY_HTTPS_ISSUER`         | TLS issuer (internal, acme)       | internal            |
| `CADDY_HTTPS_ALLOW_ANY_HOST` | Allow any host for TLS            | false               |
| `CADDY_LOG_SIZE`             | Log file max size                 | 100mb               |
| `CADDY_LOG_KEEP`             | Number of log files to keep       | 5                   |
| `WWW_ROOT_PATH`              | Web root path                     | /var/www/sites      |
| `WWW_USER`                   | WWW and SSH user in the container | admin               |
| `WWW_GROUP`                  | WWW group in the container        | www-data            |
| `HTTP_PORT`                  | HTTP port in host                 | 8080                |
| `HTTPS_PORT`                 | HTTPS port in host                | 8443                |
| `SSH_PORT`                   | SSH port in host                  | 2222                |

## Domain Logic

The server handles domains in the following way:

1. **Development domains**: Any domain ending with `.local` (e.g., `www.example.com.local`)
   - Maps to the same directory as its production counterpart.
   - Uses internal self-signed certificates.

2. **Production domains**:
   - Redirects from non-www to www for second-level domains.
   - Automatically obtains and manages Let's Encrypt certificates (issuer `acme`).

## Troubleshooting

### SSL Certificate Issues

If you're having issues with SSL certificates in development:

- Ensure your browser trusts self-signed certificates.
- Try using HTTP instead of HTTPS for local development.

### Permissions Issues

If you encounter permission issues:

```bash
docker exec -it derafu-sites-server-python-caddy chown -R admin:www-data /var/www/sites
```

### Logs Location

Logs are available in the container and can be accessed with:

```bash
docker exec -it derafu-sites-server-python-caddy cat /var/log/caddy/access.log
```

## Advanced Usage

### Custom Caddy Configuration

For advanced configurations, modify the Caddyfile at `config/caddy/Caddyfile`.

### Using with Fabric

**TODO**: Soon.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This package is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
