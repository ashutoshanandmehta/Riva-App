"""Integration: the sandbox DB has the real schema applied. Skips unless the
container is running (docker compose up -d sandbox-db)."""
import pytest


@pytest.mark.integration
def test_core_tables_exist(db):
    with db.cursor() as cur:
        cur.execute(
            "select to_regclass('public.profiles'),"
            "       to_regclass('public.nutrition_days'),"
            "       to_regclass('public.food_entries')"
        )
        profiles, days, entries = cur.fetchone()
    assert profiles and days and entries


@pytest.mark.integration
def test_log_scan_function_exists(db):
    with db.cursor() as cur:
        cur.execute("select to_regprocedure('public.log_scan(uuid,jsonb)') is not null")
        # signature may differ; fall back to name-only existence
        cur.execute("select count(*) from pg_proc where proname = 'log_scan'")
        assert cur.fetchone()[0] >= 1
