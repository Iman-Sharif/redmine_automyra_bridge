#!/usr/bin/env bash
set -euo pipefail

REDMICA_APP=${REDMICA_APP:-redmica-app}
REDMICA_DB_CONTAINER=${REDMICA_DB_CONTAINER:-redmica-db}
REDMICA_DB=${REDMICA_DB:-redmica}
REDMICA_DB_USER=${REDMICA_DB_USER:-redmica}
REDMICA_VOLUME=${REDMICA_VOLUME:-migration_redmica_postgres_data}
REDMICA_URL=${REDMICA_URL:-http://127.0.0.1:4000/login}

REDMINE_APP=${REDMINE_APP:-redmine-redmine-1}
REDMINE_DB_CONTAINER=${REDMINE_DB_CONTAINER:-redmine-postgres-1}
REDMINE_DB=${REDMINE_DB:-redmine}
REDMINE_DB_USER=${REDMINE_DB_USER:-redmine}
REDMINE_VOLUME=${REDMINE_VOLUME:-redmine_redmine_postgres_data}
REDMINE_URL=${REDMINE_URL:-http://127.0.0.1:4001/login}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

require_container_running() {
  local container="$1"
  local running
  running=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)
  [[ "$running" == "true" ]] || fail "Container $container is not running"
}

require_volume_mounted() {
  local container="$1"
  local expected_volume="$2"
  local destination="$3"
  local mounted
  mounted=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "'"$destination"'"}}{{.Name}}{{end}}{{end}}' "$container" 2>/dev/null || true)
  [[ "$mounted" == "$expected_volume" ]] || fail "$container does not mount $expected_volume at $destination (saw: ${mounted:-none})"
}

require_http_ok() {
  local url="$1"
  local label="$2"
  local status
  status=$(curl -sS -o /dev/null -w '%{http_code}' "$url" || true)
  [[ "$status" =~ ^(200|302)$ ]] || fail "$label did not return HTTP 200/302 at $url (saw: $status)"
}

psql_value() {
  local container="$1"
  local user="$2"
  local db="$3"
  local sql="$4"
  docker exec "$container" psql -U "$user" -d "$db" -Atc "$sql"
}

require_count() {
  local container="$1"
  local user="$2"
  local db="$3"
  local table="$4"
  local expected="$5"
  local actual
  actual=$(psql_value "$container" "$user" "$db" "select count(*) from ${table};")
  [[ "$actual" == "$expected" ]] || fail "$db.$table expected $expected rows, saw $actual"
  printf 'OK: %s.%s = %s\n' "$db" "$table" "$actual"
}

require_zero_orphans_redmica() {
  local query="
select coalesce(sum(count), 0) from (
  select count(*) from issues i left join projects p on p.id = i.project_id where p.id is null
  union all select count(*) from issues i left join issue_statuses s on s.id = i.status_id where s.id is null
  union all select count(*) from issues i left join trackers t on t.id = i.tracker_id where t.id is null
  union all select count(*) from issues i left join users u on u.id = i.author_id where u.id is null
  union all select count(*) from journals j left join issues i on i.id = j.journalized_id where j.journalized_type = 'Issue' and i.id is null
  union all select count(*) from wikis w left join projects p on p.id = w.project_id where p.id is null
  union all select count(*) from wiki_pages wp left join wikis w on w.id = wp.wiki_id where w.id is null
) orphan_counts(count);"
  local actual
  actual=$(psql_value "$REDMICA_DB_CONTAINER" "$REDMICA_DB_USER" "$REDMICA_DB" "$query")
  [[ "$actual" == "0" ]] || fail "Redmica orphan check expected 0, saw $actual"
  printf 'OK: Redmica orphan check = %s\n' "$actual"
}

info "Checking containers"
require_container_running "$REDMICA_APP"
require_container_running "$REDMICA_DB_CONTAINER"
require_container_running "$REDMINE_APP"
require_container_running "$REDMINE_DB_CONTAINER"

info "Checking protected DB volumes"
require_volume_mounted "$REDMICA_DB_CONTAINER" "$REDMICA_VOLUME" "/var/lib/postgresql/data"
require_volume_mounted "$REDMINE_DB_CONTAINER" "$REDMINE_VOLUME" "/var/lib/postgresql/data"

info "Checking HTTP endpoints"
require_http_ok "$REDMICA_URL" "Redmica"
require_http_ok "$REDMINE_URL" "Legacy Redmine"

info "Checking Redmica counts"
require_count "$REDMICA_DB_CONTAINER" "$REDMICA_DB_USER" "$REDMICA_DB" users 8
require_count "$REDMICA_DB_CONTAINER" "$REDMICA_DB_USER" "$REDMICA_DB" projects 27
require_count "$REDMICA_DB_CONTAINER" "$REDMICA_DB_USER" "$REDMICA_DB" issues 25
require_count "$REDMICA_DB_CONTAINER" "$REDMICA_DB_USER" "$REDMICA_DB" wiki_pages 31
require_zero_orphans_redmica

info "Checking legacy Redmine counts"
require_count "$REDMINE_DB_CONTAINER" "$REDMINE_DB_USER" "$REDMINE_DB" projects 26
require_count "$REDMINE_DB_CONTAINER" "$REDMINE_DB_USER" "$REDMINE_DB" issues 22
require_count "$REDMINE_DB_CONTAINER" "$REDMINE_DB_USER" "$REDMINE_DB" wiki_pages 29

info "Redmica/Redmine DB verification passed"
