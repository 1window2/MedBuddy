import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';

class _FakeImagePicker extends ImagePicker {
  final XFile? image;

  _FakeImagePicker(this.image);

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return image;
  }
}

class _DelayedResponseBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromFuture(
        Future<List<int>>.delayed(
          const Duration(milliseconds: 100),
          () => utf8.encode('{"medications": []}'),
        ),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  test('requestPrescriptionImage preserves OCR metadata from backend',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/prescription.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);

    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/upload-prescription');
      return http.Response(
        jsonEncode({
          'prescription_date': '2026-07-08',
          'raw_medication_count': 2,
          'parsed_medication_count': 1,
          'skipped_medication_count': 1,
          'medications': [
            {
              'drug_name': '프루코프정',
              'raw_drug_name': '포루코프정',
              'name_confidence': 0.92,
              'name_correction_source': 'local_catalog_ocr_vowel_variant',
              'dosage_per_time': '1',
              'daily_frequency': '3',
              'total_days': '5',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = PrescriptionAnalysisControl(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(XFile(imageFile.path)),
      client: client,
    );
    addTearDown(control.dispose);

    final schedules = await control.requestPrescriptionImageFromGallery();

    expect(schedules, hasLength(1));
    expect(schedules!.first.medicationName, '프루코프정');
    expect(schedules.first.rawMedicationName, '포루코프정');
    expect(schedules.first.nameConfidence, 0.92);
    expect(
      schedules.first.nameCorrectionSource,
      'local_catalog_ocr_vowel_variant',
    );
    expect(schedules.first.hasNameCorrection, isTrue);
    expect(control.lastRawMedicationCount, 2);
    expect(control.lastParsedMedicationCount, 1);
    expect(control.lastSkippedMedicationCount, 1);
  });

  test('requestPrescriptionImage derives skipped count fallback', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-empty-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/prescription.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);

    final client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode({
          'rawMedicationCount': 3,
          'parsedMedicationCount': 0,
          'medications': [],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = PrescriptionAnalysisControl(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(XFile(imageFile.path)),
      client: client,
    );
    addTearDown(control.dispose);

    final schedules = await control.requestPrescriptionImageFromGallery();

    expect(schedules, isEmpty);
    expect(control.lastRawMedicationCount, 3);
    expect(control.lastParsedMedicationCount, 0);
    expect(control.lastSkippedMedicationCount, 3);
  });

  test('analyzePrescriptionImage times out while reading a stalled body',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-timeout-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/prescription.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);

    final control = PrescriptionAnalysisControl(
      client: _DelayedResponseBodyClient(),
      requestTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(control.dispose);

    expect(
      () => control.analyzePrescriptionImage(
        XFile(imageFile.path),
        imageSource: ImageSource.gallery,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
