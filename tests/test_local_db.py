import os
import sqlite3
import tempfile
from datetime import datetime

import storage.local_db as db


class TestLocalDB:
    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._original_dir = db.DB_DIR
        self._original_path = db.DB_PATH
        db.DB_DIR = self._tmpdir
        db.DB_PATH = os.path.join(self._tmpdir, "test.db")

    def teardown_method(self):
        db.DB_DIR = self._original_dir
        db.DB_PATH = self._original_path
        test_db = os.path.join(self._tmpdir, "test.db")
        if os.path.exists(test_db):
            os.remove(test_db)

    def test_init_creates_tables_and_columns(self):
        db.init_db()
        conn = sqlite3.connect(db.DB_PATH)
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        table_names = {t[0] for t in tables}
        assert "meetings" in table_names
        assert "dictations" in table_names

        dictation_columns = {
            row[1] for row in conn.execute("PRAGMA table_info(dictations)").fetchall()
        }
        meeting_columns = {
            row[1] for row in conn.execute("PRAGMA table_info(meetings)").fetchall()
        }
        assert {"word_count", "source", "started_at", "ended_at"} <= dictation_columns
        assert {"word_count", "source"} <= meeting_columns
        conn.close()

    def test_migrate_backfills_word_counts(self):
        conn = sqlite3.connect(db.DB_PATH)
        conn.executescript(
            """
            CREATE TABLE meetings (
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
                created_at TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE dictations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                duration_seconds REAL,
                raw_text TEXT,
                app_context TEXT,
                created_at TEXT DEFAULT (datetime('now'))
            );
            """
        )
        conn.execute(
            "INSERT INTO dictations (timestamp, duration_seconds, raw_text, app_context) VALUES (?, ?, ?, ?)",
            ("2026-03-11T10:00:00", 2.0, "hello local world", "test"),
        )
        conn.execute(
            """INSERT INTO meetings
               (title, start_time, end_time, duration_seconds, raw_transcript, formatted_notes)
               VALUES (?, ?, ?, ?, ?, ?)""",
            ("Test Meeting", "2026-03-11T10:00:00", "2026-03-11T10:10:00", 600, "meeting words here", "notes"),
        )
        conn.commit()
        conn.close()

        db.migrate_db()

        conn = sqlite3.connect(db.DB_PATH)
        dictation_row = conn.execute("SELECT word_count FROM dictations").fetchone()
        meeting_row = conn.execute("SELECT word_count FROM meetings").fetchone()
        assert dictation_row[0] == 3
        assert meeting_row[0] == 3
        conn.close()

    def test_save_and_get_meeting(self):
        db.init_db()
        start = datetime(2026, 3, 5, 10, 0, 0)
        end = datetime(2026, 3, 5, 10, 30, 0)
        meeting_id = db.save_meeting(
            title="Test Meeting",
            start_time=start,
            end_time=end,
            raw_transcript="You: hello\nOthers: hi",
            formatted_notes="# Test Meeting\n\nSummary here",
        )
        assert meeting_id == 1

        meetings = db.get_recent_meetings(limit=5)
        assert len(meetings) == 1
        assert meetings[0]["title"] == "Test Meeting"
        assert meetings[0]["duration_seconds"] == 1800.0
        assert meetings[0]["word_count"] == 4

    def test_save_dictation_returns_id_and_counts_words(self):
        db.init_db()
        dictation_id = db.save_dictation("hello world again", duration=2.5, app_context="terminal")
        assert dictation_id == 1
        conn = sqlite3.connect(db.DB_PATH)
        row = conn.execute("SELECT word_count, source FROM dictations").fetchone()
        assert row[0] == 3
        assert row[1] == "dictation"
        conn.close()

    def test_get_recent_dictations(self):
        db.init_db()
        db.save_dictation("first line", duration=1.0)
        db.save_dictation("second line", duration=2.0)
        dictations = db.get_recent_dictations(limit=1)
        assert len(dictations) == 1
        assert dictations[0]["raw_text"] == "second line"

    def test_multiple_meetings_ordered_by_recent(self):
        db.init_db()
        for i in range(3):
            db.save_meeting(
                title=f"Meeting {i}",
                start_time=datetime(2026, 3, 5, 10 + i, 0, 0),
                end_time=datetime(2026, 3, 5, 10 + i, 30, 0),
                raw_transcript=f"transcript {i}",
                formatted_notes=f"notes {i}",
            )
        meetings = db.get_recent_meetings(limit=2)
        assert len(meetings) == 2
        assert meetings[0]["title"] == "Meeting 2"

    def test_get_recent_activity_unifies_dictations_and_meetings(self):
        db.init_db()
        db.save_dictation("dictation text", duration=1.0, ended_at=datetime(2026, 3, 11, 11, 0, 0))
        db.save_meeting(
            title="Meeting A",
            start_time=datetime(2026, 3, 11, 12, 0, 0),
            end_time=datetime(2026, 3, 11, 12, 30, 0),
            raw_transcript="meeting transcript",
            formatted_notes="notes",
        )
        activity = db.get_recent_activity(limit=10)
        assert [row["kind"] for row in activity] == ["meeting", "dictation"]
        assert db.get_recent_activity(limit=10, filter_kind="dictation")[0]["kind"] == "dictation"
