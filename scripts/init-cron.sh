#!/bin/bash
# This script runs once during PostgreSQL initialization
# Start cron daemon for automated backups
crond -l 2
echo "Cron daemon started for automated backups"
