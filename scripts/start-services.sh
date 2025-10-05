#!/bin/bash
set -e

# Start cron daemon
crond -l 2
echo "Cron daemon started"

# Start PostgreSQL using the default entrypoint
exec docker-entrypoint.sh postgres
