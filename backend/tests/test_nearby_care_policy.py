# File Name: test_nearby_care_policy.py
# Role: Direct regression coverage for shared nearby-care calculations and dependency direction.

import ast
from datetime import datetime
from pathlib import Path

import pytest

from services.nearby_care_policy import (
    format_time,
    haversine_distance,
    is_open_now,
    minutes_until_close,
    parse_minutes,
)


# Function Name: test_time_parsing_preserves_provider_compatibility
# Description: Keeps legacy pharmacy parsing and explicit 24:00 closing support unchanged.
# Parameters: value: Provider text; allow_24: Closing flag; expected: Parsed minutes or unknown.
# Returns: None.
@pytest.mark.parametrize("value,allow_24,expected", [
    ("900", False, 540), ("09:30", False, 570), ("", False, None),
    ("2400", False, None), ("24:00", True, 1440), ("2401", True, None),
    ("0960", False, None), ("2500", True, None), ("0000", False, 0),
])
def test_time_parsing_preserves_provider_compatibility(
    value: str, allow_24: bool, expected: int | None,
) -> None:
    assert parse_minutes(value, allow_24=allow_24) == expected


# Function Name: test_open_interval_boundaries_and_unknown_hours
# Description: Preserves exclusive closing, overnight carryover, all-day and unknown status.
# Parameters: hour, minute: Query time; start, end: Today's interval; previous: Yesterday's interval;
#   opened: Expected status; remaining: Expected minutes until closing.
# Returns: None.
@pytest.mark.parametrize("hour,minute,start,end,previous,opened,remaining", [
    (9, 0, 540, 1080, (None, None), True, 540),
    (18, 0, 540, 1080, (None, None), False, None),
    (23, 30, 1320, 120, (None, None), True, 150),
    (1, 0, 1320, 120, (None, None), False, None),
    (1, 0, None, None, (1320, 120), True, 60),
    (2, 0, None, None, (1320, 120), None, None),
    (12, 0, None, None, (None, None), None, None),
    (12, 0, 0, 0, (None, None), True, None),
    (12, 0, 0, 1440, (None, None), True, None),
    (12, 0, 540, 540, (None, None), False, None),
])
def test_open_interval_boundaries_and_unknown_hours(
    hour: int, minute: int, start: int | None, end: int | None,
    previous: tuple[int | None, int | None], opened: bool | None,
    remaining: int | None,
) -> None:
    arguments = dict(
        now=datetime(2026, 9, 29, hour, minute),
        start_minutes=start, end_minutes=end,
        previous_start_minutes=previous[0], previous_end_minutes=previous[1],
    )
    assert is_open_now(**arguments) is opened
    assert minutes_until_close(is_open_now=opened, **arguments) == remaining


# Function Name: test_display_and_distance_are_feature_independent
# Description: Checks midnight labels, missing data and symmetric geographic distance.
# Parameters: None.
# Returns: None.
def test_display_and_distance_are_feature_independent() -> None:
    assert [format_time(value) for value in (None, 0, 570, 1440)] == [
        None, "00:00", "09:30", "24:00",
    ]
    assert haversine_distance(37.5, 127, 37.5, 127) == 0
    assert haversine_distance(0, 0, 0, 1) == pytest.approx(111.195, abs=0.001)
    assert haversine_distance(37.5, 127, 35.2, 129) == pytest.approx(
        haversine_distance(35.2, 129, 37.5, 127),
    )


# Function Name: test_nearby_care_dependency_direction
# Description: Prevents controller-to-controller imports and infrastructure dependencies in pure policy.
# Parameters: None.
# Returns: None.
def test_nearby_care_dependency_direction() -> None:
    backend = Path(__file__).resolve().parents[1]
    for relative, allowed in (
        ("services/nearby_care_policy.py", {"math", "datetime"}),
        ("boundaries/holiday_lookup_boundary.py", {"datetime", "typing"}),
    ):
        tree = ast.parse((backend / relative).read_text())
        imports = {
            name.name.split(".")[0]
            for node in ast.walk(tree) if isinstance(node, ast.Import)
            for name in node.names
        } | {
            (node.module or "").split(".")[0]
            for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)
        }
        assert imports <= allowed
    peer_controllers = {
        "controls.check_nearby_hospital_control",
        "controls.check_nearby_pharmacy_control",
    }
    for module in (
        "check_nearby_hospital_control", "check_nearby_pharmacy_control",
        "hospital_department_search",
    ):
        path = backend / f"controls/{module}.py"
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom):
                assert node.module not in peer_controllers
                if node.module == "controls":
                    assert all(f"controls.{name.name}" not in peer_controllers for name in node.names)
            elif isinstance(node, ast.Import):
                assert all(name.name not in peer_controllers for name in node.names)
