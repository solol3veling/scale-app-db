FROM postgres:15-alpine

# Install required utilities for backups and cron
RUN apk add --no-cache \
    postgresql-client \
    dcron \
    bash \
    gzip \
    curl \
    aws-cli

# Create directories for scripts and backups
RUN mkdir -p /scripts /backups

# Copy backup and cron scripts
COPY scripts/ /scripts/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Set up cron
COPY scripts/crontab /etc/crontabs/root

# Use PostgreSQL init system to start cron
COPY scripts/init-cron.sh /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/init-cron.sh
