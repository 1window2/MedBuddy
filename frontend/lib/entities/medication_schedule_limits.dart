// File Name: medication_schedule_limits.dart
// Role: Defines the medication course length and start-date limits shared by the schedule editing screens.

// Longest medication course, in days, that the server accepts.
const int maxMedicationCourseDays = 3650;

// Number of days after today up to which a course may start.
const int _latestStartDateOffsetDays = 365;

// Function Name: isValidMedicationCourseDays
// Description: Checks that a course length is a whole number of days from 1 to maxMedicationCourseDays.
// Parameters:
// - days (int?): Course length in days; null when the input could not be read as a number.
// Returns:
// - True only for a value from 1 to 3650 inclusive.
bool isValidMedicationCourseDays(int? days) =>
    days != null && days >= 1 && days <= maxMedicationCourseDays;

// Function Name: earliestMedicationStartDate
// Description: Provides the earliest prescription or start date the schedule screens accept.
// Parameters:
// - None.
// Returns:
// - Local midnight of 1 January 2000.
DateTime earliestMedicationStartDate() => DateTime(2000);

// Function Name: latestMedicationStartDate
// Description: Provides the latest prescription or start date the schedule screens accept: the calendar day 365 days after the given moment, with the time of day removed.
// Parameters:
// - now (DateTime): Current local date and time.
// Returns:
// - Local midnight of the day that is 365 days after the day of now.
DateTime latestMedicationStartDate(DateTime now) =>
    DateTime(now.year, now.month, now.day + _latestStartDateOffsetDays);
