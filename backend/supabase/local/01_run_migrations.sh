#!/bin/bash
# Applies the real Supabase migrations into the sandbox DB, in filename order,
# after 00_roles_and_auth.sql has stubbed the auth schema + roles.
set -euo pipefail
for f in /supabase-migrations/*.sql; do
  echo "sandbox-db: applying $(basename "$f")"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
done
echo "sandbox-db: migrations applied."
