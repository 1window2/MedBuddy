// File Name: json_value_reader_test.dart
// Role: Regression coverage for the shared loosely typed JSON number and text readers.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/json_value_reader.dart';

// Function Name: main
// Description:
// - Register table cases for readJsonDouble, readJsonTruncatedInt, readJsonTextOr and
//   readJsonTextOrNull over every JSON-decoded value kind.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Each row: raw value, readJsonDouble, readJsonTruncatedInt, readJsonTextOr(.., 'fb'),
  // readJsonTextOrNull.
  final rows = <(Object?, double?, int?, String, String?)>[
    (7, 7.0, 7, '7', '7'),
    (16.0, 16.0, 16, '16.0', '16.0'),
    (2.9, 2.9, 2, '2.9', '2.9'),
    (-2.9, -2.9, -2, '-2.9', '-2.9'),
    (' 12 ', 12.0, 12, '12', '12'),
    ('\t1.5\n', 1.5, null, '1.5', '1.5'),
    ('abc', null, null, 'abc', 'abc'),
    ('', null, null, 'fb', null),
    ('   ', null, null, 'fb', null),
    (null, null, null, 'fb', null),
    (true, null, null, 'true', 'true'),
    (<Object>[1], null, null, '[1]', '[1]'),
    (<String, Object>{'a': 1}, null, null, '{a: 1}', '{a: 1}'),
  ];

  for (final (index, (value, asDouble, asInt, textOr, textOrNull))
      in rows.indexed) {
    // Function Name: test callback
    // Description:
    // - Expected behavior: the four readers return the values in this table row.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('row $index reads ${value.runtimeType} the same way', () {
      expect(readJsonDouble(value), asDouble);
      expect(readJsonTruncatedInt(value), asInt);
      expect(readJsonTextOr(value, 'fb'), textOr);
      expect(readJsonTextOrNull(value), textOrNull);
    });
  }
}
