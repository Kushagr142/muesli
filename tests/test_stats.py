import os
import tempfile
from datetime import date, datetime, timedelta

import storage.local_db as db
import storage.stats as stats
from storage.text_metrics import count_words


class TestStats:
    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._original_dir = db.DB_DIR
        self._original_path = db.DB_PATH
        db.DB_DIR = self._tmpdir
        db.DB_PATH = os.path.join(self._tmpdir, "test.db")
        stats._get_conn = db._get_conn

    def teardown_method(self):
        db.DB_DIR = self._original_dir
        db.DB_PATH = self._original_path

    def test_count_words_normalizes_whitespace(self):
        assert count_words("") == 0
        assert count_words("hello   world") == 2
        assert count_words("line one\nline two") == 4

    def test_dictation_stats_and_streaks(self):
        db.init_db()
        today = date.today()
        db.save_dictation(
            "one two three",
            duration=30,
            started_at=datetime.combine(today - timedelta(days=2), datetime.min.time()),
            ended_at=datetime.combine(today - timedelta(days=2), datetime.min.time()),
        )
        db.save_dictation(
            "four five",
            duration=30,
            started_at=datetime.combine(today - timedelta(days=1), datetime.min.time()),
            ended_at=datetime.combine(today - timedelta(days=1), datetime.min.time()),
        )
        db.save_dictation(
            "six seven eight nine",
            duration=60,
            started_at=datetime.combine(today, datetime.min.time()),
            ended_at=datetime.combine(today, datetime.min.time()),
        )

        result = stats.get_dictation_stats()
        assert result["total_words"] == 9
        assert result["total_sessions"] == 3
        assert result["average_words_per_session"] == 3.0
        assert result["average_wpm"] == 4.5
        assert result["current_streak_days"] == 3
        assert result["longest_streak_days"] == 3

    def test_meeting_stats_remain_separate(self):
        db.init_db()
        db.save_meeting(
            title="Planning",
            start_time=datetime(2026, 3, 11, 10, 0, 0),
            end_time=datetime(2026, 3, 11, 10, 10, 0),
            raw_transcript="alpha beta gamma delta",
            formatted_notes="notes",
        )
        result = stats.get_meeting_stats()
        assert result["total_meetings"] == 1
        assert result["total_words"] == 4
        assert result["average_words_per_meeting"] == 4.0
        assert result["average_wpm"] == 0.4

    def test_home_stats_include_recent_dictations(self):
        db.init_db()
        db.save_dictation("hello there", duration=10)
        result = stats.get_home_stats()
        assert result["dictation"]["total_sessions"] == 1
        assert len(result["last_10_dictations"]) == 1
