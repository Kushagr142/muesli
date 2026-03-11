from __future__ import annotations

from datetime import date, datetime, timedelta

from storage.local_db import _get_conn, get_recent_activity, get_recent_dictations


def _safe_avg(numerator: float, denominator: float) -> float:
    if denominator <= 0:
        return 0.0
    return numerator / denominator


def _parse_iso_day(raw_value: str | None) -> date | None:
    if not raw_value:
        return None
    return datetime.fromisoformat(raw_value).date()


def _compute_streak(days: list[date]) -> tuple[int, int]:
    unique_days = sorted(set(days))
    if not unique_days:
        return 0, 0

    longest = 1
    current_run = 1
    for previous, current in zip(unique_days, unique_days[1:]):
        if current == previous + timedelta(days=1):
            current_run += 1
        else:
            longest = max(longest, current_run)
            current_run = 1
    longest = max(longest, current_run)

    today = date.today()
    streak_anchor = today if unique_days[-1] == today else today - timedelta(days=1)
    current = 0
    cursor = streak_anchor
    day_set = set(unique_days)
    while cursor in day_set:
        current += 1
        cursor -= timedelta(days=1)
    return current, longest


def get_dictation_stats() -> dict:
    conn = _get_conn()
    row = conn.execute(
        """
        SELECT
            COUNT(*) AS total_sessions,
            COALESCE(SUM(word_count), 0) AS total_words,
            COALESCE(SUM(duration_seconds), 0) AS total_duration_seconds,
            MIN(timestamp) AS first_used_at,
            MAX(timestamp) AS last_used_at
        FROM dictations
        """
    ).fetchone()
    day_rows = conn.execute(
        "SELECT DISTINCT date(timestamp) AS used_day FROM dictations ORDER BY used_day ASC"
    ).fetchall()
    conn.close()

    total_sessions = int(row["total_sessions"] or 0)
    total_words = int(row["total_words"] or 0)
    total_duration_seconds = float(row["total_duration_seconds"] or 0.0)
    days = [_parse_iso_day(day_row["used_day"]) for day_row in day_rows]
    days = [day for day in days if day is not None]
    current_streak_days, longest_streak_days = _compute_streak(days)

    return {
        "total_words": total_words,
        "total_sessions": total_sessions,
        "average_words_per_session": round(_safe_avg(total_words, total_sessions), 1),
        "average_wpm": round(_safe_avg(total_words, total_duration_seconds / 60.0), 1),
        "current_streak_days": current_streak_days,
        "longest_streak_days": longest_streak_days,
        "days_used": len(days),
        "first_used_at": row["first_used_at"],
        "last_used_at": row["last_used_at"],
    }


def get_meeting_stats() -> dict:
    conn = _get_conn()
    row = conn.execute(
        """
        SELECT
            COUNT(*) AS total_meetings,
            COALESCE(SUM(word_count), 0) AS total_words,
            COALESCE(SUM(duration_seconds), 0) AS total_duration_seconds
        FROM meetings
        """
    ).fetchone()
    conn.close()

    total_meetings = int(row["total_meetings"] or 0)
    total_words = int(row["total_words"] or 0)
    total_duration_seconds = float(row["total_duration_seconds"] or 0.0)
    return {
        "total_words": total_words,
        "total_meetings": total_meetings,
        "total_duration_seconds": total_duration_seconds,
        "average_words_per_meeting": round(_safe_avg(total_words, total_meetings), 1),
        "average_wpm": round(_safe_avg(total_words, total_duration_seconds / 60.0), 1),
    }


def get_home_stats() -> dict:
    return {
        "dictation": get_dictation_stats(),
        "meetings": get_meeting_stats(),
        "recent_activity_count": len(get_recent_activity(limit=20)),
        "last_10_dictations": get_recent_dictations(limit=10),
    }
