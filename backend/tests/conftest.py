"""Shared test fixtures. Unit tests need no external services; integration
tests target the local sandbox DB at localhost:5433 only (and skip if it's
not running)."""
import os

import pytest

SANDBOX_DSN = os.environ.get(
    "SANDBOX_DB_DSN", "postgresql://dev:dev@localhost:5433/appdev"
)


@pytest.fixture
def db():
    """A connection to the sandbox DB, or skip if it isn't up."""
    psycopg = pytest.importorskip("psycopg")
    try:
        conn = psycopg.connect(SANDBOX_DSN, connect_timeout=2)
    except Exception:
        pytest.skip("sandbox DB not running — `docker compose up -d sandbox-db`")
    yield conn
    conn.close()
