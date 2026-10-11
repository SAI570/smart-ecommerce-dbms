#!/usr/bin/env bash
# Create the database, load schema + data, install the web app's dependencies.
#   ./setup.sh                 (uses DB_USER=postgres, DB_NAME=smart_ecommerce)
set -e
DB_NAME=${DB_NAME:-smart_ecommerce}
DB_USER=${DB_USER:-postgres}
cd "$(dirname "$0")/sql"
psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME" -c "CREATE DATABASE $DB_NAME"
psql -U "$DB_USER" -d "$DB_NAME" -q -f 00_install_all.sql
cd ../tests && psql -U "$DB_USER" -d "$DB_NAME" -q -t -A -f test_core.sql 2>&1 | grep -E "PASS|FAIL|ALL TESTS" | sed 's/^psql:[^ ]* //'
cd ../app && pip install -r requirements.txt
echo
echo "Done. Start the web app with:   cd app && DB_USER=$DB_USER DB_PASSWORD=... python app.py"
