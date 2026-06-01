#!/usr/bin/env bash
set -euo pipefail

db_host="${REDMINE_DB_POSTGRES:-${REDMINE_DB_MYSQL:-}}"

if [[ -z "${db_host}" ]]; then
  >&2 printf 'Refusing to run: database host is not configured.\n'
  exit 1
fi

if [[ "${db_host}" =~ (prod|production|live) ]]; then
  >&2 printf 'Refusing to run against non-test database host: %s\n' "${db_host}"
  exit 1
fi

if [[ "${db_host}" != "postgres" && "${db_host}" != "db" && "${db_host}" != "localhost" && "${db_host}" != "127.0.0.1" ]]; then
  >&2 printf 'Refusing to run against unexpected database host: %s\n' "${db_host}"
  exit 1
fi

cat > /usr/src/redmine/config/database.yml <<EOF
test:
  adapter: postgresql
  database: redmine_test
  host: ${REDMINE_DB_POSTGRES:-localhost}
  port: ${REDMINE_DB_PORT:-5432}
  username: ${REDMINE_DB_USERNAME:-redmine}
  password: "${REDMINE_DB_PASSWORD:-redmine}"
  encoding: utf8
EOF

if ! ruby -e "require 'mocha/minitest'" >/dev/null 2>&1; then
  gem install mocha -N
fi

bundle exec rake db:drop db:create RAILS_ENV=test DISABLE_DATABASE_ENVIRONMENT_CHECK=1
bundle exec rake db:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
