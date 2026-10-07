// File Name: json_value_reader.dart
// Role: Decodes loosely typed JSON field values shared by entity parsers.

// Function Name: readJsonText
// Description: Converts any field value to trimmed text.
// Parameters:
// - value (dynamic): Raw JSON field value.
// Returns:
// - The trimmed text, or an empty string when the value is absent.
String readJsonText(dynamic value) => value?.toString().trim() ?? '';

// Function Name: readJsonInt
// Description: Reads an integer field sent as a number or numeric text.
// Parameters:
// - value (dynamic): Raw JSON field value.
// Returns:
// - The integer, or null when the value is absent or not an integer.
int? readJsonInt(dynamic value) =>
    value is int ? value : int.tryParse(readJsonText(value));

// Function Name: readJsonBool
// Description: Reads a flag sent as a boolean, a number or true/1/yes text.
// Parameters:
// - value (dynamic): Raw JSON field value.
// Returns:
// - True only for true, nonzero numbers and true/1/yes text.
bool readJsonBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final text = readJsonText(value).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

// Function Name: readJsonDate
// Description: Parses date text, treating blank or "정보 없음" placeholders as absent.
// Parameters:
// - value (dynamic): Raw JSON field value.
// Returns:
// - The parsed date, or null when the value is absent or invalid.
DateTime? readJsonDate(dynamic value) {
  final text = readJsonText(value);
  if (text.isEmpty || text == '정보 없음') {
    return null;
  }
  return DateTime.tryParse(text);
}

// Function Name: formatJsonDate
// Description: Serializes a calendar date as YYYY-MM-DD.
// Parameters:
// - value (DateTime?): Optional calendar date.
// Returns:
// - The formatted date, or null when no date is supplied.
String? formatJsonDate(DateTime? value) {
  if (value == null) {
    return null;
  }
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
