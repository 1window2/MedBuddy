// 파일명: prescription_input_race_test.dart
// 역할: 처방전 사진 선택·로컬 OCR·임시 파일 정리가 취소나 늦은 응답에 안전한지 검증한다.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/services/prescription_local_ocr_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// 클래스명: _DeferredPicker
// 역할: 화면 취소나 재진입 후 사진 선택 완료를 재현하는 선택기 대역이다.
// 주요 책임:
// - 모든 선택 요청을 테스트가 완료하는 동일 Future에 연결한다.
// 속성:
// - result(Completer<XFile?>): 선택 사진 또는 취소 결과를 전달할 신호.
class _DeferredPicker extends ImagePicker {
  final result = Completer<XFile?>();

  // 함수이름: pickImage
  // 함수역할:
  // - 외부 선택기를 열지 않고 테스트가 result를 완료할 때까지 대기한다.
  // 매개변수:
  // - source(ImageSource): 선택 출처; 이 대역에서는 무시한다.
  // - maxWidth / maxHeight(double?): 이미지 크기 제한; 실제 변환은 수행하지 않는다.
  // - imageQuality(int?): 요청 압축 품질; 이 대역에서는 무시한다.
  // - preferredCameraDevice(CameraDevice): 인터페이스 호환용 카메라 선택.
  // - requestFullMetadata(bool): 인터페이스 호환용 메타데이터 요청 여부.
  // 반환값:
  // - Future<XFile?>: 주입한 사진 또는 취소 null; result가 오류로 완료되면 그대로 전달한다.
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) => result.future;
}

// 클래스명: _LocalOcr
// 역할: OCR 진입 경로와 완료 순서를 제어하는 로컬 인식 대역이다.
// 주요 책임:
// - 요청 경로를 기록하고 선택적 대기 뒤 고정 비식별 텍스트를 반환한다.
// 속성:
// - paths(List<String>): 인식을 시작한 이미지 경로 목록.
// - started(Completer<void>): 최초 인식이 시작됐음을 알리는 신호.
// - gate(Completer<void>?): 인식 완료를 지연하는 선택적 신호.
class _LocalOcr implements PrescriptionLocalOcrBoundary {
  final paths = <String>[];
  final started = Completer<void>();
  Completer<void>? gate;

  // 함수이름: recognizeAndMask
  // 함수역할:
  // - 경로를 기록하고 최초 진입을 알린 뒤 gate가 있으면 해제될 때까지 기다린다.
  // 매개변수:
  // - path(String): 인식을 요청한 이미지 경로; 파일 내용은 읽지 않는다.
  // 반환값:
  // - Future<LocalPrescriptionOcrResult>: 영역 목록이 빈 고정 test 텍스트 결과.
  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String path) async {
    paths.add(path);
    if (!started.isCompleted) started.complete();
    await gate?.future;
    return const LocalPrescriptionOcrResult(maskedText: 'test', regions: []);
  }
}

// 클래스명: _TemporaryPath
// 역할: 사진 정리의 허용 범위를 테스트 임시 폴더로 고정한다.
// 주요 책임:
// - 운영체제 경로 조회 대신 지정한 폴더를 반환한다.
// 속성:
// - path(String): 테스트가 관리하는 임시 저장 경로.
class _TemporaryPath extends PathProviderPlatform {
  // 함수이름: _TemporaryPath
  // 함수역할:
  // - 삭제 범위 검증에 사용할 임시 폴더 경로를 저장한다.
  // 매개변수:
  // - path(String): 이미 생성된 테스트 폴더.
  // 반환값:
  // - _TemporaryPath: 고정 경로를 제공하는 플랫폼 대역.
  _TemporaryPath(this.path);
  final String path;

  // 함수이름: getTemporaryPath
  // 함수역할:
  // - 실제 플랫폼에 접근하지 않고 지정된 임시 저장 루트를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<String?>: 생성자에서 받은 null이 아닌 경로.
  @override
  Future<String?> getTemporaryPath() async => path;
}

// 함수이름: main
// 함수역할:
// - 지연 사진 선택과 OCR 대역으로 작업 무효화 및 임시 사본 정리 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final reusedPath in [false, true]) {
    // 함수이름: test 콜백
    // 함수역할:
    // - 취소된 갤러리 선택이 새 촬영 뒤 완료되면 같은 경로 여부와 무관하게 새 사진·원본을 보존하며 OCR과 업로드는 새 촬영 한 번만 실행하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    test(
      'late picker preserves newer capture (same path=$reusedPath)',
      () async {
        final directory = Directory.systemTemp.createTempSync('reentry-race-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final current = File('${directory.path}/current.jpg')
          ..writeAsBytesSync([1]);
        final original = reusedPath
            ? current
            : (File('${directory.path}/gallery-original.jpg')
                ..writeAsBytesSync([2]));
        final previousProvider = PathProviderPlatform.instance;
        final cache = Directory('${directory.path}/cache')..createSync();
        PathProviderPlatform.instance = _TemporaryPath(cache.path);
        addTearDown(() => PathProviderPlatform.instance = previousProvider);
        final picker = _DeferredPicker();
        final ocr = _LocalOcr();
        var uploads = 0;
        final client = MockClient((_) async {
          uploads++;
          return http.Response('{"medications":[]}', 200);
        });
        final control = InputPrescription(
          imagePicker: picker,
          client: client,
          localOcrBoundary: ocr,
        );
        addTearDown(() async {
          await control.clearSelectedImage();
          control.dispose();
          client.close();
        });
        final oldRequest = control.requestPrescriptionImageFromGallery();
        control.cancelPendingRequests();
        await control.requestCapturedPrescriptionImage(XFile(current.path));
        picker.result.complete(XFile(original.path));
        await oldRequest;
        expect(control.lastSelectedImagePath, current.path);
        expect(control.lastSelectedImageOwnedByApp, isTrue);
        expect(current.existsSync(), isTrue);
        expect(original.existsSync(), isTrue);
        expect(ocr.paths, [current.path]);
        expect(uploads, 1);
      },
    );
  }

  for (final action in ['cancel', 'clear', 'dispose']) {
    // 함수이름: test 콜백
    // 함수역할:
    // - 선택 대기 중 취소·선택 지우기·폐기를 하면 늦은 선택은 OCR·업로드·선택 알림을 시작하지 않고 임시 사진을 정리하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    test(
      'gallery completion after $action never starts OCR or upload',
      () async {
        final directory = Directory.systemTemp.createTempSync('input-race-');
        final image = File('${directory.path}/picked.jpg')
          ..writeAsBytesSync([1]);
        final previousProvider = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _TemporaryPath(directory.path);
        addTearDown(() {
          PathProviderPlatform.instance = previousProvider;
          directory.deleteSync(recursive: true);
        });
        final picker = _DeferredPicker();
        final ocr = _LocalOcr();
        var uploads = 0;
        var selections = 0;
        final client = MockClient((_) async {
          uploads++;
          return http.Response('{"medications":[]}', 200);
        });
        final control = InputPrescription(
          imagePicker: picker,
          client: client,
          localOcrBoundary: ocr,
        );
        addTearDown(() async {
          await control.clearSelectedImage();
          if (action != 'dispose') control.dispose();
          client.close();
        });
        final request = control.requestPrescriptionImageFromGallery(
          onImageSelected: () => selections++,
        );
        switch (action) {
          case 'cancel':
            control.cancelPendingRequests();
          case 'clear':
            await control.clearSelectedImage();
          case 'dispose':
            control.dispose();
        }
        picker.result.complete(XFile(image.path));
        await request;
        expect(ocr.paths, isEmpty);
        expect(uploads, 0);
        expect(selections, 0);
        expect(control.lastSelectedImagePath, isEmpty);
        expect(image.existsSync(), isFalse);
      },
    );
  }

  // 함수이름: test 콜백
  // 함수역할:
  // - 이전 OCR 정리를 기다리는 새 촬영까지 취소하면 두 요청 모두 StateError로 끝나고 두 번째 OCR·업로드를 시작하지 않으며 사본을 정리하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'capture waiting for old OCR cleanup cannot restart after cancel',
    () async {
      final directory = Directory.systemTemp.createTempSync('capture-race-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final first = File('${directory.path}/first.jpg')..writeAsBytesSync([1]);
      final second = File('${directory.path}/second.jpg')
        ..writeAsBytesSync([2]);
      final ocr = _LocalOcr()..gate = Completer<void>();
      var uploads = 0;
      final client = MockClient((_) async {
        uploads++;
        return http.Response('{"medications":[]}', 200);
      });
      final control = InputPrescription(client: client, localOcrBoundary: ocr);
      addTearDown(() async {
        await control.clearSelectedImage();
        control.dispose();
        client.close();
      });
      final firstRequest = control.requestCapturedPrescriptionImage(
        XFile(first.path),
      );
      final firstAssertion = expectLater(
        firstRequest,
        throwsA(isA<StateError>()),
      );
      await ocr.started.future;
      final secondRequest = control.requestCapturedPrescriptionImage(
        XFile(second.path),
      );
      final secondAssertion = expectLater(
        secondRequest,
        throwsA(isA<StateError>()),
      );
      control.cancelPendingRequests();
      ocr.gate!.complete();
      await firstAssertion;
      await secondAssertion;
      expect(ocr.paths, [first.path]);
      expect(uploads, 0);
      expect(control.lastSelectedImagePath, isEmpty);
      expect(second.existsSync(), isFalse);
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 업로드 후 취소·선택 정리 중 도착한 성공 응답에 약 개수가 있어도 인식 개수와 영역 목록을 다시 채우지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('late cancelled HTTP response does not restore parse counts', () async {
    final directory = Directory.systemTemp.createTempSync('response-race-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/capture.jpg')..writeAsBytesSync([1]);
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final client = MockClient((_) {
      sent.complete();
      return response.future;
    });
    final control = InputPrescription(
      client: client,
      localOcrBoundary: _LocalOcr(),
    );
    addTearDown(() async {
      await control.clearSelectedImage();
      control.dispose();
      client.close();
    });
    final request = control.requestCapturedPrescriptionImage(XFile(image.path));
    final assertion = expectLater(request, throwsA(isA<StateError>()));
    await sent.future;
    control.cancelPendingRequests();
    final cleanup = control.clearSelectedImage();
    response.complete(
      http.Response('{"medications":[],"raw_medication_count":9}', 200),
    );
    await assertion;
    await cleanup;
    expect(control.lastRawMedicationCount, 0);
    expect(control.lastRecognizedTextRegions, isEmpty);
  });
}
