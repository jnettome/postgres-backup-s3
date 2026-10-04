#! /bin/sh

set -eu
set -o pipefail

source ./env.sh

echo "Creating backup of $POSTGRES_DATABASE database..."
pg_dump --format=custom \
        -h $POSTGRES_HOST \
        -p $POSTGRES_PORT \
        -U $POSTGRES_USER \
        -d $POSTGRES_DATABASE \
        $PGDUMP_EXTRA_OPTS \
        > db.dump

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_DATABASE}_${timestamp}.dump"

if [ -n "$PASSPHRASE" ]; then
  echo "Encrypting backup..."
  rm -f db.dump.gpg
  gpg --symmetric --batch --passphrase "$PASSPHRASE" db.dump
  rm db.dump
  local_file="db.dump.gpg"
  s3_uri="${s3_uri_base}.gpg"
else
  local_file="db.dump"
  s3_uri="$s3_uri_base"
fi

echo "Uploading backup to $S3_BUCKET..."
aws $aws_args s3 cp "$local_file" "$s3_uri"
rm "$local_file"

echo "Backup complete."

if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "Sending notification to Discord..."
  export timestamp s3_uri
  python3 - <<'PY'
import json, os, urllib.request
content = "[**backup**] of {db} database completed on {ts}. URL: {uri}".format(
    db=os.environ["POSTGRES_DATABASE"],
    ts=os.environ["timestamp"],
    uri=os.environ["s3_uri"],
)
req = urllib.request.Request(
    os.environ["DISCORD_WEBHOOK_URL"],
    data=json.dumps({"content": content}).encode(),
    headers={"Content-Type": "application/json", "User-Agent": "postgres-backup-s3"},
)
urllib.request.urlopen(req)
PY
  echo "Notification sent."
fi

if [ -n "$BACKUP_KEEP_DAYS" ]; then
  sec=$((86400*BACKUP_KEEP_DAYS))
  date_from_remove=$(date -d "@$(($(date +%s) - sec))" +%Y-%m-%d)
  backups_query="Contents[?LastModified<='${date_from_remove} 00:00:00'].{Key: Key}"

  echo "Removing old backups from $S3_BUCKET..."
  aws $aws_args s3api list-objects \
    --bucket "${S3_BUCKET}" \
    --prefix "${S3_PREFIX}" \
    --query "${backups_query}" \
    --output text \
    | xargs -n1 -t -I 'KEY' aws $aws_args s3 rm s3://"${S3_BUCKET}"/'KEY'
  echo "Removal complete."
fi
