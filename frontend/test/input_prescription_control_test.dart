// File Name: input_prescription_control_test.dart
// Role: Regression coverage for local prescription OCR, sensitive-file cleanup, and analysis HTTP
//   failures.
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
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/user_facing_error_message.dart';

// Class Name: _FakeImagePicker
// Role: Image-picker substitute with a preselected file or cancellation result.
// Responsibilities:
// - Return the configured selection while ignoring real platform image-selection options.
class _FakeImagePicker extends ImagePicker {
  final XFile? image;

  // Function Name: _FakeImagePicker
  // Description:
  // - Store the image-selection outcome without accessing camera or gallery UI.
  // Parameters:
  // - image (XFile?): Configured image selection or image bytes under test.
  // Returns:
  // - An image picker returning the supplied file or null.
  _FakeImagePicker(this.image);

  // Function Name: pickImage
  // Description:
  // - Return the configured selection while ignoring real platform image-selection options.
  // Parameters:
  // - source (ImageSource): Camera or gallery source requested by the caller. Accepted but not consumed
  //   by this fixture.
  // - maxWidth (double?): Maximum picker image width accepted for API compatibility. Accepted but not
  //   consumed by this fixture.
  // - maxHeight (double?): Maximum picker image height accepted for API compatibility. Accepted but not
  //   consumed by this fixture.
  // - imageQuality (int?): Requested image quality accepted by the picker contract. Accepted but not
  //   consumed by this fixture.
  // - preferredCameraDevice (CameraDevice): Preferred lens accepted by the picker interface. Accepted
  //   but not consumed by this fixture.
  // - requestFullMetadata (bool): Whether full image metadata was requested by the caller. Accepted but
  //   not consumed by this fixture.
  // Returns:
  // - The configured XFile, or null for cancellation.
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

// 클래스명: _FakePrescriptionLocalOcrBoundary
// 역할: 지정된 마스킹 텍스트와 OCR 영역을 제공하는 로컬 인식 대역.
// 주요 책임:
// - 실제 이미지 처리 없이 주입한 OCR 텍스트와 영역을 제공한다.
class _FakePrescriptionLocalOcrBoundary
    implements PrescriptionLocalOcrBoundary {
  final LocalPrescriptionOcrResult result;

  // 함수이름: _FakePrescriptionLocalOcrBoundary
  // 함수역할:
  // - 이미지 인식 대신 반환할 마스킹 텍스트와 영역 목록을 보관한다.
  // 매개변수:
  // - result (LocalPrescriptionOcrResult): 대역이 반환할 마스킹 OCR 텍스트와 영역.
  // 반환값:
  // - 고정 OCR 결과를 가진 대역.
  _FakePrescriptionLocalOcrBoundary({
    this.result = const LocalPrescriptionOcrResult(
      maskedText: '조제일자 2026-07-25\n테스트정 1 2 3',
      regions: [],
    ),
  });

  // 함수이름: recognizeAndMask
  // 함수역할:
  // - 실제 이미지 처리 없이 주입한 OCR 텍스트와 영역을 제공한다.
  // 매개변수:
  // - imagePath (String): OCR 경계가 전달받는 로컬 처방 이미지 경로. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 생성자에 지정한 LocalPrescriptionOcrResult.
  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath) async {
    return result;
  }
}

// Class Name: _BlockingPrescriptionLocalOcrBoundary
// Role: OCR stub with explicit start and completion barriers for file-lifetime checks.
// Responsibilities:
// - Signal OCR start and wait for test release before returning masked prescription text.
class _BlockingPrescriptionLocalOcrBoundary
    implements PrescriptionLocalOcrBoundary {
  final Completer<void> started = Completer<void>();
  final Completer<void> allowCompletion = Completer<void>();

  // Function Name: recognizeAndMask
  // Description:
  // - Signal OCR start and wait for test release before returning masked prescription text.
  // Parameters:
  // - imagePath (String): Local prescription image path accepted by the OCR boundary. Accepted but not
  //   consumed by this fixture.
  // Returns:
  // - Fixed local OCR output after allowCompletion resolves.
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

// Function Name: _disposeControl
// Description:
// - Await selected-image cleanup before disposing the prescription control.
// Parameters:
// - control (InputPrescription): Injected use-case control owned by the test.
// Returns:
// - Completion after file cleanup and disposal.
Future<void> _disposeControl(InputPrescription control) async {
  await control.clearSelectedImage();
  control.dispose();
}

// Class Name: _DelayedResponseBodyClient
// Role: HTTP client with an immediately available header and delayed response body.
// Responsibilities:
// - Delay the JSON response body by 100 ms to exercise body-read timeouts.
class _DelayedResponseBodyClient extends http.BaseClient {
  // Function Name: send
  // Description:
  // - Delay the JSON response body by 100 ms to exercise body-read timeouts.
  // Parameters:
  // - request (http.BaseRequest): HTTP request intercepted instead of reaching the server. Accepted but
  //   not consumed by this fixture.
  // Returns:
  // - HTTP 200 with a delayed empty-medications JSON stream.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromFuture(
        Future<List<int>>.delayed(
          const Duration(milliseconds: 100),
          // Function Name: Future<List<int>>.delayed callback
          // Description:
          // - Produce the delayed empty-medication JSON body after the header has already been delivered.
          // Parameters:
          // - None.
          // Returns:
          // - UTF-8 bytes for the empty-medications payload.
          () => utf8.encode('{"medications": []}'),
        ),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

// 클래스명: _AbortAwareClient
// 역할: 취소 신호까지 처방 분석 응답을 대기시키고 시작·취소 여부를 기록하는 HTTP 대역.
// 주요 책임:
// - 요청 시작을 알리고 취소 신호를 기다린 뒤 취소 기록과 499 응답을 남긴다.
// 속성:
// - wasAborted (bool): HTTP 취소 신호를 관찰했는지 여부.
class _AbortAwareClient extends http.BaseClient {
  bool wasAborted = false;
  final Completer<void> started = Completer<void>();

  // 함수이름: send
  // 함수역할:
  // - 요청 시작을 알리고 취소 신호를 기다린 뒤 취소 기록과 499 응답을 남긴다.
  // 매개변수:
  // - request (http.BaseRequest): 실제 서버 전송 대신 가로챈 HTTP 요청.
  // 반환값:
  // - 취소 신호 이후의 빈 HTTP 499 스트림.
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

// Function Name: main
// Description:
// - Register regression cases for local prescription OCR, sensitive-file cleanup, and analysis HTTP
//   failures.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  for (final disposeDuringOcr in [false, true]) {
    // Function Name: cancellation during OCR regression
    // Description: Exiting during OCR prevents upload and preserves capture cleanup.
    // Parameters: None; disposeDuringOcr selects explicit cancellation or disposal.
    // Returns: Completion of cancellation and file-lifetime assertions.
    test('cancels before upload during OCR (dispose=$disposeDuringOcr)', () async {
      final directory = await Directory.systemTemp.createTemp('medbuddy-ocr-cancel-');
      addTearDown(() => directory.delete(recursive: true));
      final image = File('${directory.path}/capture.jpg');
      await image.writeAsBytes([1, 2, 3]);
      final ocr = _BlockingPrescriptionLocalOcrBoundary();
      var uploads = 0;
      final client = MockClient((_) async {
        uploads++;
        return http.Response('{"medications":[]}', 200);
      });
      addTearDown(client.close);
      final control = InputPrescription(client: client, localOcrBoundary: ocr);
      final request = control.requestCapturedPrescriptionImage(XFile(image.path));
      final assertion = expectLater(request, throwsA(isA<StateError>()));
      await ocr.started.future;
      final cleanup = control.clearSelectedImage();
      if (disposeDuringOcr) {
        control.dispose();
      } else {
        control.cancelPendingRequests();
      }
      expect(await image.exists(), isTrue);
      ocr.allowCompletion.complete();
      await assertion;
      await cleanup;
      expect(uploads, 0);
      expect(control.lastRecognizedTextRegions, isEmpty);
      expect(await image.exists(), isFalse);
      if (!disposeDuringOcr) control.dispose();
    });
  }

  for (final error in <Object>[
    http.ClientException('connection closed'),
    const SocketException('connection refused'),
    const ApiContractMismatchException('incompatible-test-version'),
    const AuthenticationUnavailableException(),
    const FormatException('malformed response'),
  ]) {
    // 함수이름: test 콜백
    // 함수역할: 원래 서버·인증·파싱 오류를 보존하고 연결 오류로 일괄 변환하지 않는지 확인한다.
    // 매개변수: 없음. 반환값: Future<void>: 예외 종류와 사용자 안내 확인 완료.
    test(
      'recognition preserves ${error.runtimeType} for error guidance',
      () async {
        final client = MockClient(
          // 함수이름: MockClient 콜백
          // 함수역할: 검사할 네트워크 또는 응답 처리 예외를 발생시킨다.
          // 매개변수: request (http.Request): 분석 요청. 반환값: 오류로 완료하는 Future.
          (request) async => throw error,
        );
        final control = InputPrescription(
          imagePicker: _FakeImagePicker(XFile('test-prescription.png')),
          localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
          client: client,
        );
        addTearDown(client.close);
        // 함수이름: addTearDown 콜백
        // 함수역할: 테스트 제어기의 이미지 참조와 자원을 정리한다.
        // 매개변수: 없음. 반환값: Future<void>: 자원 정리 완료.
        addTearDown(() => _disposeControl(control));
        await expectLater(
          control.requestPrescriptionImageFromGallery(),
          throwsA(same(error)),
        );
        final guidance = UserFacingErrorMessage.resolve(
          error,
          isEnglish: false,
        );
        if (error is http.ClientException || error is SocketException) {
          expect(guidance, contains('인터넷 연결'));
        } else {
          expect(guidance, isNot(contains('인터넷 연결')));
          expect(guidance, isNot(contains('서버 연결에 실패')));
        }
      },
    );
  }

  // 함수이름: test 콜백
  // 함수역할: 잘못된 JSON 응답이 실제 파싱 오류로 전달되는지 확인한다.
  // 매개변수: 없음. 반환값: Future<void>: 예외 검증 완료.
  test(
    'malformed prescription JSON is not reported as a connection error',
    () async {
      final client = MockClient(
        // 함수이름: MockClient 콜백
        // 함수역할: HTTP는 성공했지만 JSON 형식이 잘못된 응답을 제공한다.
        // 매개변수: request (http.Request): 분석 요청. 반환값: 비정상 JSON 응답.
        (request) async => http.Response('not json', 200),
      );
      final control = InputPrescription(
        imagePicker: _FakeImagePicker(XFile('test-prescription.png')),
        localOcrBoundary: _FakePrescriptionLocalOcrBoundary(),
        client: client,
      );
      addTearDown(client.close);
      // 함수이름: addTearDown 콜백
      // 함수역할: 테스트 제어기의 자원을 정리한다.
      // 매개변수: 없음. 반환값: Future<void>: 정리 완료.
      addTearDown(() => _disposeControl(control));
      await expectLater(
        control.requestPrescriptionImageFromGallery(),
        throwsFormatException,
      );
    },
  );
  // Function Name: test callback
  // Description:
  // - Verify that a captured prescription enters local OCR without invoking the image picker.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('촬영된 처방전 파일은 이미지 선택기 없이 로컬 OCR로 처리한다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-captured-prescription-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/captured.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    var selectedCallbackCount = 0;

    // Function Name: MockClient callback
    // Description:
    // - Assert local masked-text analysis and return a dated prescription batch with one recognized
    //   schedule.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with the batch ID, prescription date, and medication row.
    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/analyze-prescription-text');
      expect(request.body, contains('테스트정'));
      return http.Response(
        jsonEncode({
          'prescription_date': '2026-07-25',
          'prescription_batch_id': 'batch_1234567890abcdef',
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
      localOcrBoundary: _FakePrescriptionLocalOcrBoundary(
        result: const LocalPrescriptionOcrResult(
          maskedText: '테스트정 1 2 3',
          regions: [
            RecognizedTextRegion(
              category: 'recognized_text',
              text: '테스트정',
              box2d: [120, 80, 240, 920],
            ),
          ],
        ),
      ),
    );
    // Function Name: addTearDown callback
    // Description:
    // - Clear the selected prescription image and dispose its control after the case.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of image cleanup and control disposal.
    addTearDown(() => _disposeControl(control));

    final schedules = await control.requestCapturedPrescriptionImage(
      XFile(imageFile.path),
      // 함수이름: onImageSelected 콜백
      // 함수역할:
      // - 이미지 선택 완료 콜백 횟수를 기록한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 없음; 선택 콜백 횟수가 증가한다.
      onImageSelected: () {
        selectedCallbackCount += 1;
      },
    );

    expect(selectedCallbackCount, 1);
    expect(schedules, hasLength(1));
    expect(schedules.first.medicationName, '테스트정');
    expect(schedules.first.prescriptionBatchId, 'batch_1234567890abcdef');
    expect(control.lastSelectedImagePath, imageFile.path);
    expect(control.lastSelectedImageOwnedByApp, isTrue);
    expect(control.lastRecognizedTextRegions, hasLength(1));
    expect(control.lastRecognizedTextRegions.first.text, '테스트정');

    await control.clearSelectedImage();
    expect(await imageFile.exists(), isFalse);
  });

  // Function Name: test callback
  // Description:
  // - Verify that closing analysis never deletes the original prescription selected from the gallery.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('갤러리 처방전 원본은 분석 흐름을 닫아도 삭제하지 않는다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-gallery-prescription-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/gallery.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      // Function Name: MockClient callback
      // Description:
      // - Provide successful empty recognition output while the test focuses on source-file lifetime.
      // Parameters:
      // - _ (http.Request): Unused intercepted HTTP request.
      // Returns:
      // - HTTP 200 containing an empty medication list.
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
    // Function Name: addTearDown callback
    // Description:
    // - Clear the selected prescription image and dispose its control after the case.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of image cleanup and control disposal.
    addTearDown(() => _disposeControl(control));

    await control.requestPrescriptionImageFromGallery();
    expect(control.lastSelectedImageOwnedByApp, isFalse);

    await control.clearSelectedImage();

    expect(await imageFile.exists(), isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Verify that captured-file cleanup waits until the active OCR operation has finished.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('진행 중 OCR이 끝난 뒤 촬영 파일을 삭제한다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-active-ocr-cleanup-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
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
        // Function Name: MockClient callback
        // Description:
        // - Provide successful empty recognition output while the test focuses on source-file lifetime.
        // Parameters:
        // - _ (http.Request): Unused intercepted HTTP request.
        // Returns:
        // - HTTP 200 containing an empty medication list.
        (_) async => http.Response(
          jsonEncode({'medications': <Object>[]}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      localOcrBoundary: localOcr,
    );
    // Function Name: addTearDown callback
    // Description:
    // - Clear the selected prescription image and dispose its control after the case.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of image cleanup and control disposal.
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

  // Function Name: test callback
  // Description:
  // - Verify that medication regions and sensitive masking regions survive local OCR processing
  //   together.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('로컬 약품 영역과 개인정보 마스킹 영역을 함께 보존한다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-region-merge-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/captured.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 로컬 OCR 영역과 함께 유지할 테스트 약의 분석 일정 데이터를 제공한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
      // 반환값:
      // - 처방일과 복약 행 한 건의 HTTP 200 응답.
      (request) async => http.Response(
        jsonEncode({
          'prescription_date': '2026-07-25',
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
            RecognizedTextRegion(
              category: 'recognized_text',
              text: '테스트정',
              box2d: [120, 80, 240, 920],
            ),
          ],
        ),
      ),
    );
    // Function Name: addTearDown callback
    // Description:
    // - Clear the selected prescription image and dispose its control after the case.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of image cleanup and control disposal.
    addTearDown(() => _disposeControl(control));

    await control.requestCapturedPrescriptionImage(XFile(imageFile.path));

    expect(control.lastRecognizedTextRegions, hasLength(2));
    expect(
      // 함수이름: any 콜백
      // 함수역할:
      // - 목록 검증에 사용할 민감 OCR 영역 여부를 추출한다.
      // 매개변수:
      // - region (RecognizedTextRegion): 개인정보 또는 약품 여부를 검사할 OCR 영역.
      // 반환값:
      // - 요소의 isSensitive 값.
      control.lastRecognizedTextRegions.any((region) => region.isSensitive),
      isTrue,
    );
    expect(
      // 함수이름: any 콜백
      // 함수역할:
      // - 목록 검증에 사용할 약품 OCR 영역 여부를 추출한다.
      // 매개변수:
      // - region (RecognizedTextRegion): 개인정보 또는 약품 여부를 검사할 OCR 영역.
      // 반환값:
      // - 요소의 isMedication 값.
      control.lastRecognizedTextRegions.any((region) => region.isMedication),
      isTrue,
    );
  });

  // Function Name: test callback
  // Description:
  // - Verify that fuzzy matching retains local medication regions despite OCR spelling errors.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('OCR 오탈자가 있는 로컬 약품 영역만 유사도로 남긴다', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-local-region-filter-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/captured.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - OCR 오탈자 영역의 유사도 대응을 검사할 정상 약명을 서버 결과로 제공한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
      // 반환값:
      // - 정규 약명과 복약 일정의 HTTP 200 응답.
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
    // Function Name: addTearDown callback
    // Description:
    // - Clear the selected prescription image and dispose its control after the case.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of image cleanup and control disposal.
    addTearDown(() => _disposeControl(control));

    await control.requestCapturedPrescriptionImage(XFile(imageFile.path));

    expect(control.lastRecognizedTextRegions, hasLength(1));
    expect(control.lastRecognizedTextRegions.single.isMedication, isTrue);
    expect(control.lastRecognizedTextRegions.single.text, contains('엘타인캡슐'));
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: prescription analysis preserves medication correction metadata.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'prescription analysis preserves medication correction metadata',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'medbuddy-prescription-test-',
      );
      // Function Name: addTearDown callback
      // Description:
      // - Remove the temporary image directory after the case, including failure paths.
      // Parameters:
      // - None.
      // Returns:
      // - Completion of temporary-file cleanup.
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final imageFile = File('${tempDirectory.path}/prescription.jpg');
      await imageFile.writeAsBytes([1, 2, 3]);

      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 분석 경로를 검사하고 원문 약명·수정 근거·신뢰도·누락 집계를 응답에 포함한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
      // 반환값:
      // - OCR 수정 메타데이터와 집계가 있는 HTTP 200 응답.
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
      // Function Name: addTearDown callback
      // Description:
      // - Clear the selected prescription image and dispose its control after the case.
      // Parameters:
      // - None.
      // Returns:
      // - Completion of image cleanup and control disposal.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: prescription analysis derives skipped count fallback.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('prescription analysis derives skipped count fallback', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-empty-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/prescription.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);

    // Function Name: MockClient callback
    // Description:
    // - Omit the skipped count while supplying raw and parsed counts to exercise fallback derivation.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
    //   consumed by this fixture.
    // Returns:
    // - HTTP 200 with three raw rows and no parsed medications.
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
    // Function Name: addTearDown callback
    // Description:
    // - Clear the selected prescription image and dispose its control after the case.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of image cleanup and control disposal.
    addTearDown(() => _disposeControl(control));

    final schedules = await control.requestPrescriptionImageFromGallery();

    expect(schedules, isEmpty);
    expect(control.lastRawMedicationCount, 3);
    expect(control.lastParsedMedicationCount, 0);
    expect(control.lastSkippedMedicationCount, 3);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: prescription analysis surfaces backend timeout detail.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('prescription analysis surfaces backend timeout detail', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-backend-timeout-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/prescription.jpg');
    await imageFile.writeAsBytes([1, 2, 3]);

    // Function Name: MockClient callback
    // Description:
    // - Return a backend timeout with its explanatory detail for user-facing error mapping.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
    //   consumed by this fixture.
    // Returns:
    // - HTTP 504 with the prescription-service timeout detail.
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
    // Function Name: addTearDown callback
    // Description:
    // - Clear the selected prescription image and dispose its control after the case.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of image cleanup and control disposal.
    addTearDown(() => _disposeControl(control));

    expect(
      // Function Name: expect callback
      // Description:
      // - Run gallery recognition against the backend-timeout fixture.
      // Parameters:
      // - None.
      // Returns:
      // - A prescription-recognition Future that fails with the backend detail.
      () => control.requestPrescriptionImageFromGallery(),
      throwsA(
        isA<StateError>().having(
          // Function Name: having callback
          // Description:
          // - Select the user-facing exception message for a focused matcher assertion.
          // Parameters:
          // - error (Object): Typed exception inspected by the matcher.
          // Returns:
          // - The exception's message value.
          (error) => error.message,
          'message',
          contains('분석 실패 (504)'),
        ),
      ),
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: prescription analysis times out while reading a stalled body.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'prescription analysis times out while reading a stalled body',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'medbuddy-prescription-timeout-test-',
      );
      // Function Name: addTearDown callback
      // Description:
      // - Remove the temporary image directory after the case, including failure paths.
      // Parameters:
      // - None.
      // Returns:
      // - Completion of temporary-file cleanup.
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
      // Function Name: addTearDown callback
      // Description:
      // - Clear the selected prescription image and dispose its control after the case.
      // Parameters:
      // - None.
      // Returns:
      // - Completion of image cleanup and control disposal.
      addTearDown(() => _disposeControl(control));

      expect(
        // Function Name: expect callback
        // Description:
        // - Run gallery recognition against the delayed-body client to exercise read timeout handling.
        // Parameters:
        // - None.
        // Returns:
        // - A recognition Future that fails when body reading times out.
        () => control.requestPrescriptionImageFromGallery(),
        throwsA(isA<StateError>()),
      );
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: prescription analysis aborts an in-flight request after timeout.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'prescription analysis aborts an in-flight request after timeout',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'medbuddy-prescription-abort-test-',
      );
      // Function Name: addTearDown callback
      // Description:
      // - Remove the temporary image directory after the case, including failure paths.
      // Parameters:
      // - None.
      // Returns:
      // - Completion of temporary-file cleanup.
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
      // Function Name: addTearDown callback
      // Description:
      // - Clear the selected prescription image and dispose its control after the case.
      // Parameters:
      // - None.
      // Returns:
      // - Completion of image cleanup and control disposal.
      addTearDown(() => _disposeControl(control));

      await expectLater(
        control.requestPrescriptionImageFromGallery(),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.wasAborted, isTrue);
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: dispose aborts an in-flight prescription analysis request.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('dispose aborts an in-flight prescription analysis request', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-dispose-test-',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Remove the temporary image directory after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
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

  test('cancelPendingRequests aborts analysis without disposing control', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-cancel-test-',
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
    addTearDown(() => _disposeControl(control));

    final request = control.requestPrescriptionImageFromGallery();
    await client.started.future;
    control.cancelPendingRequests();

    await expectLater(request, throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    expect(client.wasAborted, isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: request timeout must be positive.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('request timeout must be positive', () {
    expect(
      // Function Name: expect callback
      // Description:
      // - Construct the prescription control with a zero timeout to exercise argument validation.
      // Parameters:
      // - None.
      // Returns:
      // - An argument-validation exception.
      () => InputPrescription(requestTimeout: Duration.zero),
      throwsArgumentError,
    );
  });
}
