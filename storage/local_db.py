import os
import sqlite3
from datetime import datetime

from storage.text_metrics import count_words

DB_DIR = os.path.expanduser("~/Library/Application Support/Muesli")
DB_PATH = os.path.join(DB_DIR, "muesli.db")


def _get_conn() -> sqlite3.Connection:
    os.makedirs(DB_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def _table_columns(conn: sqlite3.Connection, table_name: str) -> set[str]:
    rows = conn.execute(f"PRAGMA table_info({table_name})").fetchall()
    return {row["name"] for row in rows}


def _ensure_columns(conn: sqlite3.Connection, table_name: str, additions: dict[str, str]):
    existing = _table_columns(conn, table_name)
    for column_name, definition in additions.items():
        if column_name not in existing:
            conn.execute(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {definition}")


def _backfill_word_counts(conn: sqlite3.Connection):
    rows = conn.execute(
        "SELECT id, raw_text FROM dictations WHERE COALESCE(word_count, 0) = 0"
    ).fetchall()
    for row in rows:
        conn.execute(
            "UPDATE dictations SET word_count = ? WHERE id = ?",
            (count_words(row["raw_text"] or ""), row["id"]),
        )

    rows = conn.execute(
        "SELECT id, raw_transcript FROM meetings WHERE COALESCE(word_count, 0) = 0"
    ).fetchall()
    for row in rows:
        conn.execute(
            "UPDATE meetings SET word_count = ? WHERE id = ?",
            (count_words(row["raw_transcript"] or ""), row["id"]),
        )


def migrate_db():
    conn = _get_conn()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS meetings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            calendar_event_id TEXT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            duration_seconds REAL,
            raw_transcript TEXT,
            formatted_notes TEXT,
            mic_audio_path TEXT,
            system_audio_path TEXT,
            word_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'meeting',
            created_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS dictations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            duration_seconds REAL,
            raw_text TEXT,
            app_context TEXT,
            word_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'dictation',
            started_at TEXT,
            ended_at TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_dictations_timestamp ON dictations(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_meetings_start_time ON meetings(start_time DESC);
        """
    )

    _ensure_columns(
        conn,
        "dictations",
        {
            "word_count": "INTEGER NOT NULL DEFAULT 0",
            "source": "TEXT NOT NULL DEFAULT 'dictation'",
            "started_at": "TEXT",
            "ended_at": "TEXT",
        },
    )
    _ensure_columns(
        conn,
        "meetings",
        {
            "word_count": "INTEGER NOT NULL DEFAULT 0",
            "source": "TEXT NOT NULL DEFAULT 'meeting'",
        },
    )
    _backfill_word_counts(conn)
    conn.commit()
    conn.close()
    print(f"[db] Initialized at {DB_PATH}")


def init_db():
    migrate_db()


def save_meeting(
    title: str,
    start_time: datetime,
    end_time: datetime,
    raw_transcript: str,
    formatted_notes: str,
    calendar_event_id: str = None,
    mic_audio_path: str = None,
    system_audio_path: str = None,
) -> int:
    duration = (end_time - start_time).total_seconds()
    word_count = count_words(raw_transcript)
    conn = _get_conn()
    cursor = conn.execute(
        """INSERT INTO meetings
           (title, calendar_event_id, start_time, end_time, duration_seconds,
            raw_transcript, formatted_notes, mic_audio_path, system_audio_path, word_count, source)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            title,
            calendar_event_id,
            start_time.isoformat(),
            end_time.isoformat(),
            duration,
            raw_transcript,
            formatted_notes,
            mic_audio_path,
            system_audio_path,
            word_count,
            "meeting",
        ),
    )
    conn.commit()
    meeting_id = cursor.lastrowid
    conn.close()
    print(f"[db] Saved meeting #{meeting_id}: {title} ({duration:.0f}s)")
    return meeting_id


def save_dictation(
    text: str,
    duration: float,
    app_context: str = "",
    started_at: datetime | None = None,
    ended_at: datetime | None = None,
) -> int:
    ended_at = ended_at or datetime.now()
    started_at = started_at or ended_at
    word_count = count_words(text)
    conn = _get_conn()
    cursor = conn.execute(
        """INSERT INTO dictations
           (timestamp, duration_seconds, raw_text, app_context, word_count, source, started_at, ended_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            ended_at.isoformat(),
            duration,
            text,
            app_context,
            word_count,
            "dictation",
            started_at.isoformat(),
            ended_at.isoformat(),
        ),
    )
    conn.commit()
    dictation_id = cursor.lastrowid
    conn.close()
    return dictation_id


def get_recent_meetings(limit: int = 10) -> list[dict]:
    conn = _get_conn()
    rows = conn.execute(
        "SELECT * FROM meetings ORDER BY start_time DESC LIMIT ?",
        (limit,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_recent_dictations(limit: int = 10) -> list[dict]:
    conn = _get_conn()
    rows = conn.execute(
        "SELECT * FROM dictations ORDER BY timestamp DESC LIMIT ?",
        (limit,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_recent_activity(limit: int = 100, filter_kind: str = "all") -> list[dict]:
    conn = _get_conn()
    rows = conn.execute(
        """
        SELECT * FROM (
            SELECT
                id,
                'dictation' AS kind,
                timestamp,
                raw_text AS preview_text,
                raw_text AS full_text,
                '' AS title,
                duration_seconds,
                word_count
            FROM dictations
            UNION ALL
            SELECT
                id,
                'meeting' AS kind,
                start_time AS timestamp,
                raw_transcript AS preview_text,
                raw_transcript AS full_text,
                title,
                duration_seconds,
                word_count
            FROM meetings
        )
        WHERE (? = 'all' OR kind = ?)
        ORDER BY timestamp DESC
        LIMIT ?
        """,
        (filter_kind, filter_kind, limit),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def delete_dictation_history():
    conn = _get_conn()
    conn.execute("DELETE FROM dictations")
    conn.commit()
    conn.close()


def delete_meeting_history():
    conn = _get_conn()
    conn.execute("DELETE FROM meetings")
    conn.commit()
    conn.close()


def delete_all_history():
    conn = _get_conn()
    conn.execute("DELETE FROM dictations")
    conn.execute("DELETE FROM meetings")
    conn.commit()
    conn.close()
