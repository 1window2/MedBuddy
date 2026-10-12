# File Name: test_medication_dose_rhythm.py
# Role: Checks the dose-day rules against the vectors the client is tested with as well.

from datetime import date
import json
from pathlib import Path

import pytest

from services.medication_dose_rhythm import (
    read_dose_cycle,
    read_doses_per_dose_day,
    read_duration_days,
)

_VECTORS = json.loads(
    (Path(__file__).parent / "data" / "dose_rhythm_vectors.json").read_text(encoding="utf-8")
)


# Function Name: test_frequency_label_gives_the_dose_cycle_and_the_doses_per_dose_day
# Description: A frequency label yields the listed cycle and per-day dose count.
# Parameters: vector (dict) - One frequency vector.
# Returns: None.
@pytest.mark.parametrize("vector", _VECTORS["frequency"], ids=lambda vector: vector["text"] or "empty")
def test_frequency_label_gives_the_dose_cycle_and_the_doses_per_dose_day(vector: dict) -> None:
    cycle = read_dose_cycle(vector["text"])
    assert [cycle.cycle_days, list(cycle.offsets), cycle.weekday_anchored] == vector["cycle"]
    assert read_doses_per_dose_day(vector["text"]) == vector["doses"]


# Function Name: test_duration_label_is_read_with_its_unit
# Description: A duration label yields the listed number of days.
# Parameters: vector (dict) - One duration vector.
# Returns: None.
@pytest.mark.parametrize("vector", _VECTORS["duration"], ids=lambda vector: vector["text"] or "empty")
def test_duration_label_is_read_with_its_unit(vector: dict) -> None:
    assert read_duration_days(vector["text"]) == vector["days"]


# Function Name: test_dose_days_follow_the_cycle_from_the_course_start
# Description: A date is a dose day exactly when the vector says so.
# Parameters: vector (dict) - One due-date vector.
# Returns: None.
@pytest.mark.parametrize(
    "vector", _VECTORS["due"], ids=lambda vector: f'{vector["text"]}@{vector["date"]}',
)
def test_dose_days_follow_the_cycle_from_the_course_start(vector: dict) -> None:
    cycle = read_dose_cycle(vector["text"])
    assert cycle.includes(
        date.fromisoformat(vector["start"]), date.fromisoformat(vector["date"]),
    ) is vector["due"]
