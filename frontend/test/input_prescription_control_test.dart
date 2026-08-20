import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';
import 'package:medbuddy_frontend/services/prescription_local_ocr_service.dart';

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

class _FakePrescriptionLocalOcrBoundary
    implements PrescriptionLocalOcrBoundary {
  final LocalPrescriptionOcrResult result;

  _FakePrescriptionLocalOcrBoundary({
    this.result = const LocalPrescriptionOcrResult(
      maskedText: '조제일자 2026-07-25\n테스트정 1 2 3',
      regions: [],
    ),
  });

  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath) async {
    return result;
  }
}

class _BlockingPrescriptionLocalOcrBoundary
    implements PrescriptionLocalOcrBoundary {
  final Completer<void> started = Completer<void>();
  final Completer<void> allowCompletion = Completer<void>();

  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath) async {
    started.complete();
    await allowCompletion.future;
    return const LocalPrescriptionOcrResult(
      maskedText: '테스트정 1 2 3',
      regions: [],
    );
  }
}

Future<void> _disposeControl(InputPrescription control) async {
  await control.clearSelectedImage();
  control.dispose();
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

class _AbortAwareClient extends http.BaseClient {
  bool wasAborted = false;
  final Completer<void> started = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortableRequest = request as http.AbortableRequest;
    if (!started.isCompleted) {
      started.complete();
    }
    await abortableRequest.abortTrigger;
    wasAborted = true;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 499);
  }
}

void main() {
  test('촬영된 처방전 파일은 이미지 선택기 없이 OCR API로 전송한다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-captured-prescription-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/captured.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    var selectedCallbackCount = 0;

    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/analyze-prescription-text');
      expect(request.body, contains('테스트정'));
      return http.Response(
        jsonEncode({
          'prescription_date': '2026-07-25',
          'recognized_regions': [
            {
              'category': 'medication_row',
              'text': '테스트정 1정 1일 2회',
              'box_2d': [120, 80, 240, 920],
            },
          ],
          'medications': [
            {
              'drug_name': '테스트정',
              'dosage_per_time': '1',
              'daily_frequency': '2',
              'total_days': '3',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = InputPrescription(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(null),
      client: client,
      localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
    );
    addTearDown(() => _disposeControl(control));

    final schedules = await control.requestCapturedPrescriptionImage(
      XFile(imageFile.path),
      onImageSelected: () {
        selectedCallbackCount += 1;
      },
    );

    expect(selectedCallbackCount, 1);
    expect(schedules, hasLength(1));
    expect(schedules.first.medicationName, '테스트정');
    expect(control.lastSelectedImagePath, imageFile.path);
    expect(control.lastSelectedImageOwnedByApp, isTrue);
    expect(control.lastRecognizedTextRegions, hasLength(1));
    expect(control.lastRecognizedTextRegions.first.text, '테스트정 1정 1일 2회');

    await control.clearSelectedImage();
    expect(await imageFile.exists(), isFalse);
  });

  test('갤러리 처방전 원본은 분석 흐름을 닫아도 삭제하지 않는다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-gallery-prescription-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/gallery.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'medications': <Object>[]}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final control = InputPrescription(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(XFile(imageFile.path)),
      client: client,
      localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
    );
    addTearDown(() => _disposeControl(control));

    await control.requestPrescriptionImageFromGallery();
    expect(control.lastSelectedImageOwnedByApp, isFalse);

    await control.clearSelectedImage();

    expect(await imageFile.exists(), isTrue);
  });

  test('진행 중 OCR이 끝난 뒤 촬영 파일을 삭제한다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-active-ocr-cleanup-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/captured.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final localOcr = _BlockingPrescriptionLocalOcrBoundary();
    final control = InputPrescription(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(null),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'medications': <Object>[]}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      localOcrBoundary: localOcr,
    );
    addTearDown(() => _disposeControl(control));

    final analysis = control.requestCapturedPrescriptionImage(
      XFile(imageFile.path),
    );
    await localOcr.started.future;
    final cleanup = control.clearSelectedImage();
    await Future<void>.delayed(Duration.zero);

    expect(await imageFile.exists(), isTrue);

    localOcr.allowCompletion.complete();
    await analysis;
    await cleanup;

    expect(await imageFile.exists(), isFalse);
  });

  test('서버 약품 영역을 사용해도 로컬 개인정보 마스킹 영역을 보존한다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-region-merge-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/captured.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'prescription_date': '2026-07-25',
          'recognized_regions': [
            {
              'category': 'medication_row',
              'text': '테스트정 1정 1일 2회',
              'box_2d': [120, 80, 240, 920],
            },
          ],
          'medications': [
            {
              'drug_name': '테스트정',
              'dosage_per_time': '1',
              'daily_frequency': '2',
              'total_days': '3',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final control = InputPrescription(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(null),
      client: client,
      localOcrBoundary: _FakePrescriptionLocalOcrBoundary(
        result: const LocalPrescriptionOcrResult(
          maskedText: '테스트정 1 2 3',
          regions: [
            RecognizedTextRegion(
              category: 'sensitive_info',
              text: '',
              box2d: [20, 40, 80, 400],
            ),
          ],
        ),
      ),
    );
    addTearDown(() => _disposeControl(control));

    await control.requestCapturedPrescriptionImage(XFile(imageFile.path));

    expect(control.lastRecognizedTextRegions, hasLength(2));
    expect(
      control.lastRecognizedTextRegions.any((region) => region.isSensitive),
      isTrue,
    );
    expect(
      control.lastRecognizedTextRegions.any((region) => region.isMedication),
      isTrue,
    );
  });

  test('서버 좌표가 없으면 OCR 오탈자가 있는 약품 영역만 유사도로 남긴다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-local-region-filter-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/captured.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'prescription_date': '2026-07-25',
          'medications': [
            {
              'drug_name': '엘타인캡슐(에르도스테인)',
              'dosage_per_time': '1',
              'daily_frequency': '2',
              'total_days': '3',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final control = InputPrescription(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(null),
      client: client,
      localOcrBoundary: _FakePrescriptionLocalOcrBoundary(
        result: const LocalPrescriptionOcrResult(
          maskedText: '엘타인캡슐(에르도스테민) 1 2 3\n전문가와 상의하여 정해진 기간 복용하세요',
          regions: [
            RecognizedTextRegion(
              category: 'recognized_text',
              text: '엘타인캡슐(에르도스테민)',
              box2d: [120, 80, 180, 500],
            ),
            RecognizedTextRegion(
              category: 'recognized_text',
              text: '전문가와 상의하여 정해진 기간 복용하세요',
              box2d: [200, 80, 260, 500],
            ),
          ],
        ),
      ),
    );
    addTearDown(() => _disposeControl(control));

    await control.requestCapturedPrescriptionImage(XFile(imageFile.path));

    expect(control.lastRecognizedTextRegions, hasLength(1));
    expect(control.lastRecognizedTextRegions.single.isMedication, isTrue);
    expect(control.lastRecognizedTextRegions.single.text, contains('엘타인캡슐'));
  });

  test(
    'requestPrescriptionImage preserves OCR metadata from backend',
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
        expect(request.url.path, '/analyze-prescription-text');
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
      final control = InputPrescription(
        baseUrl: 'http://localhost',
        imagePicker: _FakeImagePicker(XFile(imageFile.path)),
        client: client,
        localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
      );
      addTearDown(() => _disposeControl(control));

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
    },
  );

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
    final control = InputPrescription(
      baseUrl: 'http://localhost',
      imagePicker: _FakeImagePicker(XFile(imageFile.path)),
      client: client,
      localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
    );
    addTearDown(() => _disposeControl(control));

    final schedules = await control.requestPrescriptionImageFromGallery();

    expect(schedules, isEmpty);
    expect(control.lastRawMedicationCount, 3);
    expect(control.lastParsedMedicationCount, 0);
    expect(control.lastSkippedMedicationCount, 3);
  });

  test(
    'requestPrescriptionImage surfaces backend OCR timeout detail',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'medbuddy-prescription-backend-timeout-test-',
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
          jsonEncode({'detail': '처방전 인식 서비스 응답 시간이 초과되었습니다.'}),
          504,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = InputPrescription(
        baseUrl: 'http://localhost',
        imagePicker: _FakeImagePicker(XFile(imageFile.path)),
        client: client,
        localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
      );
      addTearDown(() => _disposeControl(control));

      expect(
        () => control.requestPrescriptionImageFromGallery(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('분석 실패 (504)'),
          ),
        ),
      );
    },
  );

  test(
    'requestPrescriptionImage times out while reading a stalled body',
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

      final control = InputPrescription(
        imagePicker: _FakeImagePicker(XFile(imageFile.path)),
        client: _DelayedResponseBodyClient(),
        localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
        requestTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(() => _disposeControl(control));

      expect(
        () => control.requestPrescriptionImageFromGallery(),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'requestPrescriptionImage aborts an in-flight upload after timeout',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'medbuddy-prescription-abort-test-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final imageFile = File('${tempDirectory.path}/prescription.jpg');
      await imageFile.writeAsBytes([1, 2, 3]);
      final client = _AbortAwareClient();
      final control = InputPrescription(
        imagePicker: _FakeImagePicker(XFile(imageFile.path)),
        client: client,
        localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
        requestTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(() => _disposeControl(control));

      await expectLater(
        control.requestPrescriptionImageFromGallery(),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.wasAborted, isTrue);
    },
  );

  test('dispose aborts an in-flight prescription upload', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-dispose-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/prescription.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final client = _AbortAwareClient();
    final control = InputPrescription(
      imagePicker: _FakeImagePicker(XFile(imageFile.path)),
      client: client,
      localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
    );

    final request = control.requestPrescriptionImageFromGallery();
    await client.started.future;
    control.dispose();

    await expectLater(request, throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    expect(client.wasAborted, isTrue);
  });

  test('request timeout must be positive', () {
    expect(
      () => InputPrescription(requestTimeout: Duration.zero),
      throwsArgumentError,
    );
  });
}
