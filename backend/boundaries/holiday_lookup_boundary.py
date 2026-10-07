# File Name: holiday_lookup_boundary.py
# Role: Calendar contract independent of pharmacy and hospital controllers.

from datetime import date
from typing import Protocol


# Class Name: HolidayLookupBoundary
# Role:
# - Defines asynchronous public-holiday classification for nearby-care schedule selection.
# Responsibilities:
# - Let nearby search select holiday hours without depending on a particular calendar provider.
class HolidayLookupBoundary(Protocol):
    # Function Name: isHoliday
    # Description:
    # - Checks whether the requested date is an official public holiday.
    # Parameters:
    # - value (date): Calendar date for the requested schedule or validation.
    # Returns:
    # - True for a recognized public holiday.
    async def isHoliday(self, value: date) -> bool: ...
