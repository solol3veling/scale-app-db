#!/bin/bash
set -e

# Restore script for PostgreSQL database
# Usage: ./restore.sh <s3_backup_path_or_latest>

BACKUP_FILE="/tmp/restore_temp.sql.gz"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if backup path is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <s3_path_or_latest>"
    echo ""
    echo "Examples:"
    echo "  $0 s3://your-bucket/backups/backup_scaleapp_20250103_120000.sql.gz"
    echo "  $0 latest  # Restores the most recent backup"
    echo ""
    echo "Available S3 backups:"
    aws s3 ls "s3://${S3_BUCKET}/backups/" \
        --region "${AWS_DEFAULT_REGION:-us-east-1}" | \
        grep "backup_${POSTGRES_DB}_" || echo "No backups found"
    exit 1
fi

BACKUP_SOURCE="$1"

# If 'latest', find the most recent backup
if [ "${BACKUP_SOURCE}" == "latest" ]; then
    log "Finding latest backup in S3..."
    LATEST_BACKUP=$(aws s3 ls "s3://${S3_BUCKET}/backups/" \
        --region "${AWS_DEFAULT_REGION:-us-east-1}" | \
        grep "backup_${POSTGRES_DB}_" | \
        sort -k1,2 | \
        tail -1 | \
        awk '{print $4}')

    if [ -z "${LATEST_BACKUP}" ]; then
        log "ERROR: No backups found in S3"
        exit 1
    fi

    BACKUP_SOURCE="s3://${S3_BUCKET}/backups/${LATEST_BACKUP}"
    log "Latest backup: ${BACKUP_SOURCE}"
fi

# Download from S3
log "Downloading backup from S3: ${BACKUP_SOURCE}"
if aws s3 cp "${BACKUP_SOURCE}" "${BACKUP_FILE}" \
    --region "${AWS_DEFAULT_REGION:-us-east-1}"; then
    log "Download successful"
else
    log "ERROR: Failed to download from S3"
    exit 1
fi

# Check if file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    log "ERROR: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

log "Starting restore from: ${BACKUP_FILE}"

# Confirm restore operation (skip if CI environment)
if [ -z "${CI}" ]; then
    echo "WARNING: This will overwrite the current database: ${POSTGRES_DB}"
    echo "Press Ctrl+C to cancel, or Enter to continue..."
    read -r
fi

# Drop existing connections to the database
log "Terminating existing connections to database: ${POSTGRES_DB}"
psql -U "${POSTGRES_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();" || true

# Drop and recreate database
log "Dropping and recreating database: ${POSTGRES_DB}"
psql -U "${POSTGRES_USER}" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
psql -U "${POSTGRES_USER}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB};"

# Restore from backup
log "Restoring database from backup..."
if gunzip -c "${BACKUP_FILE}" | psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"; then
    log "Restore completed successfully"
else
    log "ERROR: Restore failed"
    exit 1
fi

# Cleanup temp file
rm -f "${BACKUP_FILE}"
log "Cleaned up temporary restore file"

log "Database restore process completed successfully"
