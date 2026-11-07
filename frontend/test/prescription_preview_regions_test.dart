// File Name: prescription_preview_regions_test.dart
// Role: Checks selection, deduplication and ordering of sensitive and medication preview regions.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_preview_regions.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';

// Function Name: region
// Description: Builds a recognized region with a ten-unit square bounding box.
// Parameters:
// - category (String): Recognition category.
// - text (String): Recognized content.
// - top, left (double): Box origin; both default to zero.
// Returns:
// - RecognizedTextRegion with the requested content and position.
RecognizedTextRegion region(
  String category,
  String text, {
  double top = 0,
  double left = 0,
}) => RecognizedTextRegion(
  category: category,
  text: text,
  box2d: [top, left, top + 10, left + 10],
);

// Function Name: main
// Description: Registers preview filtering and OCR name-match cases.
// Parameters: None.
// Returns: No value; registers synchronous tests.
void main() {
  // Function Name: test callback
  // Description:
  // - Keeps sensitive text, promotes a matching medicine name, drops dosage-only text and sorts the retained regions by position.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('sensitive regions stay and matching text becomes a medication', () {
    final regions = resolvePrescriptionPreviewRegions(
      localRegions: [
        region('recognized_text', '엘타인캡슐 300mg', top: 50),
        region('sensitive_info', '홍길동', top: 10),
        region('recognized_text', '1일 3회 식후', top: 60),
      ],
      medicationSchedules: const [MedicationSchedule(medicationName: '엘타인캡슐')],
    );
    expect(regions.map((r) => (r.category, r.text)), [
      ('sensitive_info', '홍길동'),
      ('medication_name', '엘타인캡슐 300mg'),
    ]);
  });

  // Function Name: test callback
  // Description:
  // - Accepts a one-character name error only when the recognized text retains a valid dosage-form suffix.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('a one-letter OCR error matches only text with a dosage form', () {
    // Function Name: matched
    // Description:
    // - Resolves one OCR string against the captured Tylenol schedule and returns retained text.
    // Parameters:
    // - text (String): OCR text to test.
    // Returns:
    // - List<String>: Matched region text, or an empty list when rejected.
    List<String> matched(String text) => resolvePrescriptionPreviewRegions(
      localRegions: [region('recognized_text', text)],
      medicationSchedules: const [MedicationSchedule(medicationName: '타이레놀정')],
    ).map((r) => r.text).toList();
    expect(matched('타이레놀졍'), isEmpty);
    expect(matched('타이레눌정'), ['타이레눌정']);
  });

  // Function Name: test callback
  // Description:
  // - Deduplicates identical sensitive boxes and excludes a medication candidate whose name is too short.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('short names and duplicate boxes are left out', () {
    final regions = resolvePrescriptionPreviewRegions(
      localRegions: [
        region('sensitive_info', '주민번호'),
        region('sensitive_info', '주민번호'),
        region('recognized_text', '정제'),
      ],
      medicationSchedules: const [MedicationSchedule(medicationName: '정제')],
    );
    expect(regions, hasLength(1));
    expect(regions.single.isSensitive, isTrue);
  });
}
