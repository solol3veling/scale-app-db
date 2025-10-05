#!/bin/bash
set -e

# Backup script for PostgreSQL database
# Creates compressed backups and uploads to S3 Deep Glacier Archive
# Maintains maximum 3 backups in S3, deleting oldest when limit exceeded

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/backup_${POSTGRES_DB}_${TIMESTAMP}.sql.gz"
S3_PATH="s3://${S3_BUCKET}/backups/backup_${POSTGRES_DB}_${TIMESTAMP}.sql.gz"
MAX_BACKUPS=3

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Verify S3 bucket is configured
if [ -z "${S3_BUCKET}" ]; then
    log "ERROR: S3_BUCKET environment variable is not set"
    exit 1
fi

# Start backup
log "Starting backup for database: ${POSTGRES_DB}"

# Create backup using pg_dump
if pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" | gzip > "${BACKUP_FILE}"; then
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    log "Backup created successfully: ${BACKUP_FILE} (${BACKUP_SIZE})"
else
    log "ERROR: pg_dump failed for database: ${POSTGRES_DB}"
    rm -f "${BACKUP_FILE}"
    exit 1
fi

# Upload to S3 with Deep Glacier Archive storage class
log "Uploading backup to S3: ${S3_PATH}"
if aws s3 cp "${BACKUP_FILE}" "${S3_PATH}" \
    --storage-class DEEP_ARCHIVE \
    --region "${AWS_DEFAULT_REGION:-us-east-1}"; then
    log "S3 upload successful: ${S3_PATH}"
else
    log "ERROR: S3 upload failed"
    rm -f "${BACKUP_FILE}"
    exit 1
fi

# Remove temporary local backup file
rm -f "${BACKUP_FILE}"
log "Removed temporary backup file"

# Manage S3 backup retention (keep only latest 3)
log "Checking S3 backup count..."
BACKUP_COUNT=$(aws s3 ls "s3://${S3_BUCKET}/backups/" \
    --region "${AWS_DEFAULT_REGION:-us-east-1}" | \
    grep "backup_${POSTGRES_DB}_" | wc -l)

log "Current backup count: ${BACKUP_COUNT}"

if [ "${BACKUP_COUNT}" -gt "${MAX_BACKUPS}" ]; then
    log "Backup count exceeds maximum (${MAX_BACKUPS}). Deleting oldest backups..."

    # Get oldest backups to delete
    BACKUPS_TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))

    aws s3 ls "s3://${S3_BUCKET}/backups/" \
        --region "${AWS_DEFAULT_REGION:-us-east-1}" | \
        grep "backup_${POSTGRES_DB}_" | \
        sort -k1,2 | \
        head -n "${BACKUPS_TO_DELETE}" | \
        awk '{print $4}' | \
        while read -r old_backup; do
            log "Deleting old backup: ${old_backup}"
            aws s3 rm "s3://${S3_BUCKET}/backups/${old_backup}" \
                --region "${AWS_DEFAULT_REGION:-us-east-1}"
        done

    log "Cleanup complete. Remaining backups: ${MAX_BACKUPS}"
else
    log "No cleanup needed. Current count (${BACKUP_COUNT}) is within limit (${MAX_BACKUPS})"
fi

log "Backup process completed successfully"
