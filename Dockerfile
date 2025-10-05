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

# Custom entrypoint to start cron and PostgreSQL
COPY scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["postgres"]
