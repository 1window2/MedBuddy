// 파일명: app_temp_file_retry_test.dart
// 역할: 앱 임시 사진 삭제가 Windows 잠금을 제한적으로 재시도하고 외부 파일을 보호하는지 검증한다.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/app_temp_file.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// 클래스명: _TemporaryPathProvider
// 역할: 파일 삭제의 허용 루트를 테스트 전용 캐시 폴더로 고정한다.
// 주요 책임:
// - 실제 플랫폼 경로 조회 없이 지정 경로를 반환한다.
// 속성:
// - path(String): 임시 파일 삭제가 허용되는 캐시 폴더 경로.
class _TemporaryPathProvider extends PathProviderPlatform {
  // 함수이름: _TemporaryPathProvider
  // 함수역할:
  // - 플랫폼에 노출할 임시 폴더 경로를 저장한다.
  // 매개변수:
  // - path(String): 이미 생성한 테스트 캐시 폴더.
  // 반환값:
  // - _TemporaryPathProvider: 고정 경로 제공자; 폴더를 생성하지 않는다.
  _TemporaryPathProvider(this.path);
  final String path;

  // 함수이름: getTemporaryPath
  // 함수역할:
  // - 운영체제 대신 생성자에서 받은 캐시 경로를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<String?>: 이 대역에서는 항상 null이 아닌 path 값.
  @override
  Future<String?> getTemporaryPath() async => path;
}

// 클래스명: _ControlledDeleteFile
// 역할: 파일의 실제 경로 해석과 삭제 결과를 단계별로 바꿀 수 있는 최소 대역이다.
// 주요 책임:
// - 삭제 잠금 오류와 재시도 사이의 경로 변경을 주입한다.
// 속성:
// - resolvePath(Future<String> Function()): 현재 실제 경로 조회 동작.
// - deleteFile(Future<FileSystemEntity> Function()): 삭제 또는 삭제 오류 동작.
class _ControlledDeleteFile implements File {
  // 함수이름: _ControlledDeleteFile
  // 함수역할:
  // - 경로 조회와 삭제를 서로 독립적으로 제어할 콜백을 보관한다.
  // 매개변수:
  // - resolvePath(Future<String> Function()): 정규 경로를 반환할 동작.
  // - deleteFile(Future<FileSystemEntity> Function()): 실제 삭제 또는 실패를 재현할 동작.
  // 반환값:
  // - _ControlledDeleteFile: 두 파일 작업만 구현하는 대역.
  _ControlledDeleteFile(this.resolvePath, this.deleteFile);
  final Future<String> Function() resolvePath;
  final Future<FileSystemEntity> Function() deleteFile;

  // 함수이름: resolveSymbolicLinks
  // 함수역할:
  // - 매 호출마다 주입된 경로 해석을 실행하여 재시도 중 대상 변경을 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<String>: 주입된 정규 경로 또는 경로 해석 오류.
  @override
  Future<String> resolveSymbolicLinks() => resolvePath();

  // 함수이름: delete
  // 함수역할:
  // - 주입된 삭제 작업을 실행하여 시도 횟수와 운영체제 오류를 제어한다.
  // 매개변수:
  // - recursive(bool): File 인터페이스 호환용 옵션; 이 대역에서는 사용하지 않는다.
  // 반환값:
  // - Future<FileSystemEntity>: 삭제 결과 또는 주입된 FileSystemException.
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => deleteFile();

  // 함수이름: noSuchMethod
  // 함수역할:
  // - 구현하지 않은 File 작업을 호출하면 상위 기본 동작으로 실패시킨다.
  // 매개변수:
  // - invocation(Invocation): 지원하지 않는 멤버 호출 정보.
  // 반환값:
  // - 정상 반환 없이 NoSuchMethodError를 발생시켜 대역의 예상 밖 사용을 드러낸다.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 함수이름: main
// 함수역할:
// - 실제 임시 파일에 제어 가능한 삭제 오류를 주입하는 재시도·경로 보호 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 준비·정리 훅과 비동기 테스트를 등록한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory cache;
  late File copy;
  late PathProviderPlatform originalProvider;

  // 함수이름: setUp 콜백
  // 함수역할:
  // - 독립 루트와 캐시 사진 사본을 만들고 플랫폼 임시 경로를 해당 캐시로 교체한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 테스트 파일 준비 완료; 원래 경로 제공자는 정리를 위해 보관한다.
  setUp(() async {
    root = await Directory.systemTemp.createTemp('temp-cleanup-retry-');
    cache = await Directory('${root.path}/cache').create();
    copy = await File('${cache.path}/photo.png').writeAsString('copy');
    originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPathProvider(cache.path);
  });

  // 함수이름: tearDown 콜백
  // 함수역할:
  // - 원래 플랫폼 경로 제공자를 복원하고 테스트가 만든 루트 폴더를 제거한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 파일 정리 완료; 파일 시스템 오류는 프레임워크에 전달한다.
  tearDown(() async {
    PathProviderPlatform.instance = originalProvider;
    await root.delete(recursive: true);
  });

  // 함수이름: deleteWith
  // 함수역할:
  // - 파일 생성만 대역으로 바꾸고 파일 종류 조회는 원래 IO 영역에서 실행해 삭제를 검사한다.
  // 매개변수:
  // - remove(Future<FileSystemEntity> Function()): 각 삭제 시도에 실행할 동작.
  // - resolve(Future<String> Function()?): 경로 해석 대역; 없으면 사본의 실제 경로를 해석한다.
  // 반환값:
  // - Future<bool>: deleteAppTempFile의 삭제 성공 여부.
  Future<bool> deleteWith(
    Future<FileSystemEntity> Function() remove, {
    Future<String> Function()? resolve,
  }) {
    final realIO = Zone.current;
    return IOOverrides.runZoned(
      () => deleteAppTempFile(copy.path),
      createFile: (_) =>
          _ControlledDeleteFile(resolve ?? copy.resolveSymbolicLinks, remove),
      fseGetType: (path, followLinks) => realIO.run(
        () => FileSystemEntity.type(path, followLinks: followLinks),
      ),
    );
  }

  for (final code in [32, 33]) {
    // 함수이름: test 콜백
    // 함수역할:
    // - 잠금 코드 32·33은 Windows에서 두 번 실패 후 세 번째에 삭제하며 다른 운영체제에서는 재시도 없이 파일을 남기는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    test('temporary Windows lock $code is retried then deleted', () async {
      var attempts = 0;
      final deleted = await deleteWith(() async {
        attempts++;
        if (attempts <= 2) {
          throw FileSystemException(
            'locked',
            copy.path,
            OSError('locked', code),
          );
        }
        return copy.delete();
      });
      expect(deleted, Platform.isWindows);
      expect(attempts, Platform.isWindows ? 3 : 1);
      expect(await copy.exists(), !Platform.isWindows);
    });
  }

  // 함수이름: test 콜백
  // 함수역할:
  // - 권한 오류 코드 5는 삭제를 한 번만 시도하고 false를 반환하며 사본을 그대로 남기는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('permanent access failure is not retried', () async {
    var attempts = 0;
    expect(
      await deleteWith(() async {
        attempts++;
        throw FileSystemException(
          'denied',
          copy.path,
          const OSError('denied', 5),
        );
      }),
      isFalse,
    );
    expect(attempts, 1);
    expect(await copy.exists(), isTrue);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 계속되는 잠금은 Windows에서 네 번까지만 시도하고 다른 운영체제에서는 한 번 시도한 뒤 사본을 남기는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('persistent Windows lock has a bounded retry budget', () async {
    var attempts = 0;
    expect(
      await deleteWith(() async {
        attempts++;
        throw FileSystemException(
          'locked',
          copy.path,
          const OSError('locked', 32),
        );
      }),
      isFalse,
    );
    expect(attempts, Platform.isWindows ? 4 : 1);
    expect(await copy.exists(), isTrue);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 첫 삭제 실패 뒤 정규 경로가 캐시 밖 원본을 가리키면 두 번째 삭제를 하지 않고 원본 내용과 사본을 모두 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('retry rechecks canonical containment before another delete', () async {
    final outside = await File(
      '${root.path}/original.png',
    ).writeAsString('original');
    var attempts = 0;
    var current = copy;
    expect(
      await deleteWith(() async {
        attempts++;
        current = outside;
        throw FileSystemException(
          'locked',
          copy.path,
          const OSError('locked', 32),
        );
      }, resolve: () => current.resolveSymbolicLinks()),
      isFalse,
    );
    expect(attempts, 1);
    expect(await copy.exists(), isTrue);
    expect(await outside.readAsString(), 'original');
  });
}
