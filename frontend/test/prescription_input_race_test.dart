import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/services/prescription_local_ocr_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _DeferredPicker extends ImagePicker {
  final result = Completer<XFile?>();

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

class _LocalOcr implements PrescriptionLocalOcrBoundary {
  final paths = <String>[];
  final started = Completer<void>();
  Completer<void>? gate;

  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String path) async {
    paths.add(path);
    if (!started.isCompleted) started.complete();
    await gate?.future;
    return const LocalPrescriptionOcrResult(maskedText: 'test', regions: []);
  }
}

class _TemporaryPath extends PathProviderPlatform {
  _TemporaryPath(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final reusedPath in [false, true]) {
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
