#!/bin/sh
set -eu

APP_HOME=${APP_HOME:-/usr/src/redmica}
RAILS_ENV=${RAILS_ENV:-production}
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-5432}
DB_ADAPTER=${DB_ADAPTER:-postgresql}
WAIT_FOR_DB_TIMEOUT=${WAIT_FOR_DB_TIMEOUT:-60}
RUN_DB_MIGRATIONS=${RUN_DB_MIGRATIONS:-1}
RUN_PLUGIN_MIGRATIONS=${RUN_PLUGIN_MIGRATIONS:-1}
BUNDLE_INSTALL_AT_STARTUP=${BUNDLE_INSTALL_AT_STARTUP:-0}

cd "$APP_HOME"

if [ "$BUNDLE_INSTALL_AT_STARTUP" = "1" ]; then
  echo "[entrypoint] Installing bundle dependencies at startup"
  bundle install --jobs 4 --retry 3
fi

echo "[entrypoint] Waiting for database at ${DB_HOST}:${DB_PORT}"
end=$(( $(date +%s) + WAIT_FOR_DB_TIMEOUT ))

# Check database type and wait accordingly
if [ "$DB_ADAPTER" = "postgresql" ] || [ "$DB_PORT" = "5432" ]; then
  # PostgreSQL connection check
  while ! bundle exec ruby -e '
    require "pg"
    begin
      conn = PG.connect(
        host: ENV.fetch("DB_HOST", "db"),
        port: Integer(ENV.fetch("DB_PORT", "5432")),
        user: ENV.fetch("DB_USER"),
        password: ENV.fetch("DB_PASSWORD"),
        dbname: ENV.fetch("DB_NAME")
      )
      conn.exec("SELECT 1")
      puts "db ok"
    rescue => e
      exit 1
    end
  ' >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$end" ]; then
      echo "[entrypoint] Database did not become ready in time" >&2
      exit 1
    fi
    sleep 2
  done
else
  # MySQL connection check
  while ! bundle exec ruby -rmysql2 -e 'Mysql2::Client.new(host: ENV.fetch("DB_HOST", "db"), port: Integer(ENV.fetch("DB_PORT", "3306")), username: ENV.fetch("DB_USER"), password: ENV.fetch("DB_PASSWORD"), database: ENV.fetch("DB_NAME")); puts "db ok"' >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$end" ]; then
      echo "[entrypoint] Database did not become ready in time" >&2
      exit 1
    fi
    sleep 2
  done
fi

if [ "$RUN_DB_MIGRATIONS" = "1" ]; then
  echo "[entrypoint] Running core migrations"
  bundle exec rake db:migrate RAILS_ENV="$RAILS_ENV"
fi

if [ "$RUN_PLUGIN_MIGRATIONS" = "1" ]; then
  echo "[entrypoint] Running plugin migrations"
  bundle exec rake redmine:plugins:migrate RAILS_ENV="$RAILS_ENV"
fi

echo "[entrypoint] Starting Redmica"
exec "$@"
