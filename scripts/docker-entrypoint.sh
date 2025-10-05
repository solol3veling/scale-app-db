#!/bin/bash
set -e

# Custom entrypoint script for PostgreSQL container
# Starts PostgreSQL and cron daemon for automated backups

# Start the original PostgreSQL entrypoint in the background
docker-entrypoint.sh postgres &
POSTGRES_PID=$!

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to start..."
until pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" > /dev/null 2>&1; do
    sleep 2
done

echo "PostgreSQL is ready!"

# Start cron daemon for scheduled backups
echo "Starting cron daemon for automated backups..."
crond -f -l 2 &

# Wait for PostgreSQL process
wait $POSTGRES_PID
