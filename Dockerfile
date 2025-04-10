# Use Python 3.13.1 as base
FROM python:3.13.1

# Arguments.
ARG CADDY_DEBUG=
ARG WWW_ROOT_PATH=/var/www/sites
ARG WWW_USER=admin
ARG WWW_GROUP=www-data

# Expose ports.
EXPOSE 22 80 443 9090 8000

# Run a lot of commands :)
RUN \
    \
    # Install basic dependencies.
    apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    at \
    ca-certificates \
    build-essential \
    cargo \
    cron \
    curl \
    cython3 \
    debian-archive-keyring \
    debian-keyring \
    gnupg \
    g++ \
    gcc \
    gir1.2-gdkpixbuf-2.0 \
    git \
    iputils-ping \
    libgd-dev \
    libicu-dev \
    libsqlite3-dev \
    libzip-dev \
    lsb-release \
    libcairo2 \
    libatlas-base-dev \
    libblas-dev \
    libffi-dev \
    libfreetype6-dev \
    libfribidi-dev \
    libgdk-pixbuf2.0-dev \
    libgfortran5 \
    libharfbuzz-dev \
    libjpeg-dev \
    liblapack-dev \
    libopenblas-dev \
    libpango1.0-dev \
    libpq-dev \
    libxml2-dev \
    libxslt-dev \
    logrotate \
    meson \
    nano \
    nmap \
    net-tools \
    ninja-build \
    openssh-client \
    openssh-server \
    postgresql-client \
    rustc \
    shared-mime-info \
    socat \
    screen \
    sudo \
    supervisor \
    unzip \
    vim \
    wget \
    zip \
    zlib1g-dev \
    # Install Caddy
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends caddy \
    && rm -rf /var/lib/apt/lists/* \
    \
    # Create SSH directory.
    && mkdir -p /var/run/sshd \
    \
    # Create admin user for SSH access.
    && useradd -m -d /home/${WWW_USER} -s /bin/bash ${WWW_USER} \
    && usermod -p '*' ${WWW_USER} \
    && echo "${WWW_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && chmod 0440 /etc/sudoers \
    && chmod g+w /etc/passwd \
    && mkdir -p /home/${WWW_USER}/.ssh \
    && chmod 700 /home/${WWW_USER}/.ssh \
    && ssh-keyscan -t rsa github.com >> /home/${WWW_USER}/.ssh/known_hosts \
    && chmod 600 /home/${WWW_USER}/.ssh/known_hosts \
    && chown ${WWW_USER}: /home/${WWW_USER}/.ssh/known_hosts \
    \
    # Create necessary directories for web content and give admin user access.
    && mkdir -p ${WWW_ROOT_PATH} \
    && chown -R ${WWW_USER}:${WWW_GROUP} ${WWW_ROOT_PATH} \
    && chmod 770 ${WWW_ROOT_PATH} -R \
    && ln -s ${WWW_ROOT_PATH} /home/${WWW_USER}/sites \
    \
    # Allow www-data and ${WWW_USER} users to add jobs to the at queue.
    && echo "www-data" >> /etc/at.allow \
    && echo "${WWW_USER}" >> /etc/at.allow \
    \
    # Add SSH known hosts.
    && mkdir -p /etc/ssh \
    && ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts \
    && chmod 644 /etc/ssh/ssh_known_hosts

# Copy authorized keys for the user.
COPY config/ssh/authorized_keys /home/${WWW_USER}/.ssh/authorized_keys
RUN chmod 600 /home/${WWW_USER}/.ssh/authorized_keys \
    && chown -R ${WWW_USER}:${WWW_USER} /home/${WWW_USER}/.ssh \
    \
    # Add SSH key for www-data user.
    && mkdir -p /var/www/.ssh \
    && ssh-keygen -t rsa -b 4096 -N "" -C "www-data@localhost" -f /var/www/.ssh/id_rsa -q \
    && cat /var/www/.ssh/id_rsa.pub >> /home/${WWW_USER}/.ssh/authorized_keys \
    && chown -R www-data:www-data /var/www/.ssh \
    && chmod 700 /var/www/.ssh \
    && chmod 600 /var/www/.ssh/id_rsa

# Add configuration to .bashrc of the user.
COPY config/bash/bashrc /root/add-to-bashrc
RUN cat /root/add-to-bashrc >> /home/${WWW_USER}/.bashrc \
    && rm -f /root/add-to-bashrc

# Configure Caddy.
COPY config/caddy/Caddyfile /etc/caddy/Caddyfile

# Configure SSH.
COPY config/ssh/sshd_config /etc/ssh/sshd_config

# Create log directories for Gunicorn and Caddy.
RUN mkdir -p /var/log/gunicorn /var/log/caddy \
    && chmod 777 /var/log/gunicorn /var/log/caddy

# Copy logrotate configuration.
COPY config/logrotate/gunicorn /etc/logrotate.d/gunicorn
COPY config/logrotate/caddy /etc/logrotate.d/caddy

# Copy Supervisor configuration.
COPY config/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY scripts/start_sites.sh /scripts/start_sites.sh
RUN chmod +x /scripts/start_sites.sh

RUN mkdir -p /run/gunicorn && chmod 777 /run/gunicorn

# Use Supervisor as the main process.
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
