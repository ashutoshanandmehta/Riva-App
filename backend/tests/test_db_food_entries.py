"""Integration: food_entries reads on the sandbox DB. Skips unless the
container is running (docker compose up -d sandbox-db). Everything runs inside
the fixture connection's transaction, which rolls back on close.
"""

import uuid

import pytest


def _new_user(cur, tz="America/New_York"):
    """Provision a user + profile directly. The signup trigger is skipped
    (replica mode) because the sandbox auth.users stub lacks the
    raw_user_meta_data column the trigger reads."""
    user_id = str(uuid.uuid4())
    cur.execute("SET LOCAL session_replication_role = replica")
    cur.execute("INSERT INTO auth.users (id) VALUES (%s)", (user_id,))
    cur.execute("SET LOCAL session_replication_role = DEFAULT")
    cur.execute(
        "INSERT INTO public.profiles (id, name, timezone) VALUES (%s, 'Test', %s)",
        (user_id, tz),
    )
    return user_id


@pytest.mark.integration
def test_food_entries_selectable_columns(db):
    """The columns list_food_entries reads all exist and are selectable."""
    with db.cursor() as cur:
        cur.execute(
            "SELECT day, scan_type, items, calories, protein_grams, water_ounces, created_at"
            " FROM public.food_entries WHERE false"
        )
        assert cur.description is not None


@pytest.mark.integration
def test_food_entries_returns_seeded_rows_desc(db):
    """A seeded user's accepted scans come back newest first with the wire shape."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        cur.execute(
            "INSERT INTO public.food_entries"
            " (user_id, day, scan_type, items, calories, protein_grams, created_at)"
            " VALUES (%s, '2026-07-24', 'food',"
            " '[{\"name\": \"Older item\"}]'::jsonb, 100, 2, now() - interval '1 hour')",
            (user_id,),
        )
        cur.execute(
            "INSERT INTO public.food_entries"
            " (user_id, day, scan_type, items, calories, protein_grams, created_at)"
            " VALUES (%s, '2026-07-25', 'food',"
            ' \'[{"name": "Fried Samosa Pieces"}]\'::jsonb, 180, 3, now())',
            (user_id,),
        )
        cur.execute(
            "SELECT day, scan_type, items, calories, protein_grams, water_ounces, created_at"
            " FROM public.food_entries"
            " WHERE user_id = %s AND deleted_at IS NULL"
            " ORDER BY created_at DESC",
            (user_id,),
        )
        rows = cur.fetchall()
        assert len(rows) == 2
        newest = rows[0]
        assert newest[1] == "food"
        assert newest[2] == [{"name": "Fried Samosa Pieces"}]
        assert newest[3] == 180
