"""공유 전송 시각의 확인된 운영 구간을 JSON 스냅샷으로 고정한다."""

from datetime import datetime, timedelta

from services.nearby_care_policy import is_open_now, parse_operating_hours


def build_operating_snapshot(
    *, now: datetime, today_hours: object, previous_hours: object,
    today_calendar_verified: bool, previous_calendar_verified: bool,
    operating_notes: str = "",
) -> dict[str, object]:
    """기존 운영 판정을 재사용하며 공휴일·휴게 안내의 불확실성을 추정하지 않는다."""
    if now.utcoffset() is None:
        raise ValueError("Operating snapshots require a timezone-aware server clock.")
    snapshot: dict[str, object] = {
        "status": "unknown", "as_of": now.isoformat(),
        "opens_at": None, "closes_at": None,
    }
    if operating_notes:
        return snapshot
    start, end = parse_operating_hours(today_hours if today_calendar_verified else None)
    prev_start, prev_end = parse_operating_hours(previous_hours if previous_calendar_verified else None)
    opened = is_open_now(
        now=now, start_minutes=start, end_minutes=end,
        previous_start_minutes=prev_start, previous_end_minutes=prev_end,
    )
    if opened is not True and (opened is None or not previous_calendar_verified):
        return snapshot
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    intervals: list[tuple[datetime, datetime]] = []
    # 전날·당일의 확인된 구간이 겹치거나 맞닿으면 실제로 끊기지 않는 운영 구간으로 합친다.
    for day, first, last in (
        (midnight - timedelta(days=1), prev_start, prev_end), (midnight, start, end),
    ):
        if first is None or last is None:
            continue
        opens_at = day + timedelta(minutes=first)
        closes_at = day + timedelta(minutes=last + (1440 if last < first else 0))
        if intervals and opens_at <= intervals[-1][1]:
            intervals[-1] = (intervals[-1][0], max(intervals[-1][1], closes_at))
        else:
            intervals.append((opens_at, closes_at))
    if opened:
        opens_at, closes_at = next(interval for interval in intervals if interval[0] <= now < interval[1])
        # 당일 0000~2400은 종료 시각이 없는 종일 운영이다. 내일 시간은 모르므로 자정을 종료로 보이지 않는다.
        if start == 0 and end == 1440:
            return {
                "status": "open", "as_of": now.isoformat(),
                "opens_at": opens_at.isoformat(), "closes_at": None,
            }
        remaining = closes_at - now
        status = "closing_soon" if timedelta(0) < remaining <= timedelta(minutes=30) else "open"
    else:
        opens_at, closes_at = intervals[-1]
        status = "before_open" if now < opens_at else "closed"
    return {
        "status": status, "as_of": now.isoformat(),
        "opens_at": opens_at.isoformat(), "closes_at": closes_at.isoformat(),
    }
