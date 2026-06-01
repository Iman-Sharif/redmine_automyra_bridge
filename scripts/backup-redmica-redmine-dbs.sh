#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT=${BACKUP_ROOT:-/opt/redmica/.sisyphus/evidence/incident-20260429-redmica-db}
BACKUP_DIR=${BACKUP_DIR:-$BACKUP_ROOT/pre-cleanup-$(date +%Y%m%d-%H%M%S)}

mkdir -p "$BACKUP_DIR"

log() {
  printf '==> %s\n' "$*"
}

backup_postgres_db() {
  local container="$1"
  local user="$2"
  local db="$3"
  local output="$BACKUP_DIR/$db.dump"

  if docker exec "$container" psql -U "$user" -d postgres -Atc "select 1 from pg_database where datname = '$db';" | grep -q 1; then
    log "Backing up $container/$db to $output"
    docker exec "$container" pg_dump -U "$user" -Fc -d "$db" > "$output"
    docker run --rm -v "$BACKUP_DIR:/backup:ro" postgres:16-bookworm pg_restore -l "/backup/$db.dump" >/dev/null
    sha256sum "$output" >> "$BACKUP_DIR/SHA256SUMS"
  else
    log "Skipping $container/$db because it does not exist"
  fi
}

log "Running pre-backup verification"
/opt/redmica/scripts/verify-redmica-redmine-dbs.sh

backup_postgres_db redmica-db redmica redmica
backup_postgres_db redmine-postgres-1 redmine redmine

for db in redmica_recovery redmica_staging redmica_test; do
  backup_postgres_db redmica-db redmica "$db"
done

log "Writing container and volume inventory"
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' > "$BACKUP_DIR/docker-containers.tsv"
docker volume ls --format '{{.Name}}' > "$BACKUP_DIR/docker-volumes.txt"
docker inspect redmica-app redmica-db redmine-redmine-1 redmine-postgres-1 > "$BACKUP_DIR/protected-container-inspect.json"

log "Backups written to $BACKUP_DIR"
