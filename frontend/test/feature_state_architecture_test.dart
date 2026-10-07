// File Name: feature_state_architecture_test.dart
// Role: Prevents feature owners from rejoining the shared facade library.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Function Name: main
// Description: Enforces the six independent feature-library boundaries.
// Parameters: None. Returns: None.
void main() {
  for (final feature in [
    'health_recommendation',
    'saved_medication',
    'schedule',
    'reminder',
    'user_setting',
    'prescription',
  ]) {
    // Function Name: feature boundary test
    // Description: Rejects facade imports and shared-library feature declarations.
    // Parameters: None. Returns: None.
    test('$feature owns state outside the facade library', () {
      final source = File(
        'lib/viewmodels/medbuddy_${feature}_view_model.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('part of')));
      expect(source, isNot(contains("'medbuddy_view_model.dart'")));
      expect(source, isNot(contains('on MedBuddyViewModel')));
      expect(source, contains('class MedBuddy'));
    });
  }
}
