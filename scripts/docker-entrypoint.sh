#!/bin/bash
set -e

# Start cron daemon for automated backups
echo "Starting cron daemon..."
crond -l 2

# Execute the original PostgreSQL entrypoint (replaces this process)
echo "Starting PostgreSQL..."
exec docker-entrypoint.sh postgres
