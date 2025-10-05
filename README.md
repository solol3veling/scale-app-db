# Scale App - PostgreSQL with S3 Deep Glacier Backups

Production PostgreSQL 15 database with automated weekly backups to S3 Deep Glacier Archive.

## Features

- 🐳 **PostgreSQL 15 Alpine** - Lightweight production database
- ☁️ **S3 Deep Glacier Archive** - Cost-optimized long-term storage
- ⏰ **Weekly Automated Backups** - Every Sunday at 02:00 UTC
- 📦 **Maximum 3 Backups** - Auto-deletes oldest when limit exceeded
- 🔐 **IAM User Authentication** - Uses AWS access keys (stored in .env)
- 🔄 **CI/CD Deployment** - GitHub Actions for VPS updates

## Quick Start

### 1. Create IAM User for Backups

**Step 1: Create IAM Policy**

Go to AWS Console → IAM → Policies → Create Policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PostgresBackupAccess",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::your-backup-bucket",
        "arn:aws:s3:::your-backup-bucket/backups/*"
      ]
    }
  ]
}
```

Name it: `PostgresBackupPolicy`

**Step 2: Create IAM User**

1. IAM → Users → Create User
2. Username: `postgres-backup-user`
3. Attach policy: `PostgresBackupPolicy`
4. Create access key → Application running outside AWS
5. **Save Access Key ID and Secret Access Key** (you won't see the secret again!)

**Step 3: Create S3 Bucket**

```bash
aws s3 mb s3://your-backup-bucket --region us-east-1
```

### 2. Setup Repository

```bash
git clone <your-repo-url> scale-app-db
cd scale-app-db
cp .env.example .env
nano .env  # Add AWS credentials and configure settings
```

### 3. Configure Environment

Edit `.env`:

```bash
# Database
POSTGRES_DB=scaleapp
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_PORT=5432

# S3 Backups (IAM User credentials)
S3_BUCKET=your-s3-bucket-name
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_DEFAULT_REGION=us-east-1
```

**⚠️ Security**: Never commit `.env` to git! It's already in `.gitignore`.

### 4. Start Database

```bash
docker compose up -d
docker compose logs -f postgres
```

## Backup System

### How It Works

1. **Schedule**: Every Sunday at 02:00 UTC (configured in `scripts/crontab`)
2. **Process**:
   - Creates compressed `pg_dump` → `/tmp/backup_scaleapp_YYYYMMDD_HHMMSS.sql.gz`
   - Uploads to S3 with `DEEP_ARCHIVE` storage class
   - Deletes temporary local file
   - Keeps only latest 3 backups in S3 (deletes oldest if > 3)

### Manual Backup

```bash
docker compose exec postgres /scripts/backup.sh
```

### List S3 Backups

```bash
aws s3 ls s3://your-bucket/backups/
```

### Storage Class: Deep Glacier Archive

- **Cost**: ~$0.00099/GB/month (99% cheaper than STANDARD)
- **Retrieval Time**: 12-48 hours
- **Use Case**: Long-term disaster recovery backups

**Note**: Deep Glacier requires restore request before download. See [Restore from Deep Glacier](#restore-from-deep-glacier) section.

## Restore

### Restore from Latest Backup

```bash
docker compose exec postgres /scripts/restore.sh latest
```

### Restore from Specific Backup

```bash
# List available backups
aws s3 ls s3://your-bucket/backups/

# Restore specific backup
docker compose exec postgres /scripts/restore.sh s3://your-bucket/backups/backup_scaleapp_20250103_020000.sql.gz
```

### Restore from Deep Glacier

Deep Glacier backups require a restore request before they can be downloaded:

```bash
# 1. Initiate restore request (choose retrieval tier)
aws s3api restore-object \
  --bucket your-bucket \
  --key backups/backup_scaleapp_20250103_020000.sql.gz \
  --restore-request '{"Days":1,"GlacierJobParameters":{"Tier":"Bulk"}}'

# Retrieval tiers:
# - Bulk: 12-48 hours, cheapest
# - Standard: 12 hours, moderate cost
# - Expedited: 1-5 minutes, expensive

# 2. Check restore status
aws s3api head-object \
  --bucket your-bucket \
  --key backups/backup_scaleapp_20250103_020000.sql.gz

# Look for: "Restore": "ongoing-request=\"false\""

# 3. Once restored, download and restore database
docker compose exec postgres /scripts/restore.sh s3://your-bucket/backups/backup_scaleapp_20250103_020000.sql.gz
```

**⚠️ Warning**: Restore is destructive - it drops and recreates the database.

## Database Access

### From Container

```bash
docker compose exec postgres psql -U postgres -d scaleapp
```

### From Host

```bash
psql -h localhost -p 5432 -U postgres -d scaleapp
```

### From Spring Boot

**application.properties**:
```properties
spring.datasource.url=jdbc:postgresql://your-vps-ip:5432/scaleapp
spring.datasource.username=postgres
spring.datasource.password=${POSTGRES_PASSWORD}

# Flyway handles migrations (not this repo)
spring.flyway.enabled=true
```

## CI/CD Deployment

### Setup GitHub Secrets

Add these in **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `VPS_SSH_KEY` | Private SSH key contents |
| `VPS_HOST` | VPS IP or hostname |
| `VPS_USER` | SSH username (e.g., `ubuntu`) |
| `DEPLOY_PATH` | `/home/ubuntu/scale-app-db` |

### Deploy

```bash
git push origin main  # Triggers auto-deployment
```

Or manually: **GitHub → Actions → Deploy PostgreSQL to VPS → Run workflow**

**What happens**:
1. Syncs code to VPS
2. Builds Docker image
3. Creates pre-deployment backup
4. Restarts container
5. Verifies health

## Monitoring

### Check Backup Logs

```bash
# View latest backup log
docker compose exec postgres tail -100 /var/log/postgres-backup.log

# View cron logs
docker compose logs postgres | grep backup
```

### Verify S3 Backups

```bash
# List backups with sizes
aws s3 ls s3://your-bucket/backups/ --human-readable

# Check backup count (should be ≤ 3)
aws s3 ls s3://your-bucket/backups/ | grep backup_scaleapp | wc -l
```

### Database Health

```bash
# Container status
docker compose ps

# Database readiness
docker compose exec postgres pg_isready -U postgres

# Database size
docker compose exec postgres psql -U postgres -d scaleapp -c "SELECT pg_size_pretty(pg_database_size('scaleapp'));"
```

### Test Backups

```bash
# Verify AWS credentials work
docker compose exec postgres aws sts get-caller-identity

# Test S3 access
docker compose exec postgres aws s3 ls s3://your-bucket/

# Manual backup test
docker compose exec postgres /scripts/backup.sh
```

## Customization

### Change Backup Schedule

Edit `scripts/crontab`:

```bash
# Weekly on Sunday at 02:00 UTC (default)
0 2 * * 0 /scripts/backup.sh 2>&1 | tee -a /var/log/postgres-backup.log

# Daily at 03:00 UTC
0 3 * * * /scripts/backup.sh 2>&1 | tee -a /var/log/postgres-backup.log

# Twice weekly (Sunday and Wednesday at 02:00)
0 2 * * 0,3 /scripts/backup.sh 2>&1 | tee -a /var/log/postgres-backup.log

# First day of month at 01:00 UTC
0 1 1 * * /scripts/backup.sh 2>&1 | tee -a /var/log/postgres-backup.log
```

Rebuild: `docker compose up -d --build`

### Change Maximum Backups

Edit `scripts/backup.sh`:

```bash
MAX_BACKUPS=5  # Change from 3 to 5
```

Restart: `docker compose restart postgres`

## Troubleshooting

### Backups Not Running

```bash
# Check cron daemon
docker compose exec postgres ps aux | grep crond

# Test backup manually
docker compose exec postgres /scripts/backup.sh

# Restart container
docker compose restart postgres
```

### S3 Upload Failing

```bash
# Verify AWS credentials
docker compose exec postgres aws sts get-caller-identity

# Test S3 access
docker compose exec postgres aws s3 ls s3://your-bucket/

# Check environment variables
docker compose exec postgres env | grep AWS
```

**Common issues**:
- Invalid AWS credentials → Check `.env` file
- Bucket doesn't exist → Create with `aws s3 mb`
- IAM permissions missing → Review IAM policy
- Wrong region → Verify `AWS_DEFAULT_REGION`

### Restore Failing

```bash
# Check if backup exists in S3
aws s3 ls s3://your-bucket/backups/

# Check if backup is in Deep Glacier (requires restore request)
aws s3api head-object --bucket your-bucket --key backups/backup_scaleapp_20250103_020000.sql.gz

# View restore logs
docker compose logs postgres | grep restore
```

### Container Won't Start

```bash
# View logs
docker compose logs postgres

# Check disk space
df -h

# Rebuild image
docker compose up -d --build
```

## Cost Optimization

### S3 Deep Glacier Pricing (us-east-1)

- **Storage**: $0.00099 per GB/month
- **PUT requests**: $0.05 per 1,000 requests
- **Retrieval**:
  - Bulk (12-48h): $0.0025 per GB
  - Standard (12h): $0.01 per GB
  - Expedited (1-5m): $0.03 per GB

### Example Monthly Cost

**Scenario**: 10GB database, 3 backups (30GB total), 4 backups/month

- **Storage**: 30GB × $0.00099 = **$0.03/month**
- **Uploads**: 4 requests × $0.05/1000 = **$0.0002/month**
- **Total**: **~$0.03/month**

**vs. STANDARD storage**: $0.69/month (23x more expensive)

### Cost Saving Tips

1. **Adjust backup frequency** - Monthly instead of weekly
2. **Reduce retention** - Keep 2 backups instead of 3
3. **Use Bulk retrieval** - Cheapest option (12-48h wait)
4. **Enable S3 Lifecycle policies** - Auto-delete after 90 days

## Repository Structure

```
scale-app-db/
├── Dockerfile                # Custom PostgreSQL with AWS CLI & cron
├── docker-compose.yml        # Service configuration
├── .env.example             # Environment template
├── .env                     # Your config (git-ignored)
├── README.md                # This file
├── .github/workflows/
│   ├── deploy.yml           # CI/CD deployment
│   └── backup-test.yml      # Weekly backup testing
└── scripts/
    ├── backup.sh            # S3 Deep Glacier backup script
    ├── restore.sh           # S3 restore script
    ├── docker-entrypoint.sh # Starts PostgreSQL + cron
    └── crontab              # Weekly schedule (Sun 02:00 UTC)
```

## Security Best Practices

### Credentials

- ✅ **Use strong passwords** - 32+ characters for `POSTGRES_PASSWORD`
- ✅ **Never commit `.env`** - Already in `.gitignore`
- ✅ **Rotate AWS keys** - Every 90 days minimum
- ✅ **Least privilege IAM** - Only S3 access, specific bucket
- ✅ **Enable MFA** - On AWS root and IAM accounts

### Network

- ✅ **Restrict database port** - Only allow application server
  ```yaml
  ports:
    - "127.0.0.1:5432:5432"  # localhost only
  ```
- ✅ **Use firewall** - UFW or iptables
  ```bash
  sudo ufw allow from <app-server-ip> to any port 5432
  ```

### S3

- ✅ **Enable bucket encryption** - Server-side AES-256
  ```bash
  aws s3api put-bucket-encryption \
    --bucket your-bucket \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'
  ```
- ✅ **Enable versioning** - Protects against accidental deletion
  ```bash
  aws s3api put-bucket-versioning \
    --bucket your-bucket \
    --versioning-configuration Status=Enabled
  ```
- ✅ **Block public access** - Ensure bucket is private
- ✅ **Enable access logging** - Audit all S3 operations

### Monitoring

- ✅ **Test restores monthly** - Verify backups are valid
- ✅ **Monitor backup success** - Check logs weekly
- ✅ **Set up alerts** - Email on backup failure
- ✅ **Document procedures** - Keep DR runbook updated

## Support

- **Issues**: Create an issue in this repository
- **PostgreSQL Docs**: https://www.postgresql.org/docs/15/
- **AWS S3 Docs**: https://docs.aws.amazon.com/s3/
- **AWS Glacier Docs**: https://docs.aws.amazon.com/amazonglacier/latest/dev/

## License

MIT
