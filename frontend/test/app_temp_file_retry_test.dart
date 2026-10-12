import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/app_temp_file.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

class _ControlledDeleteFile implements File {
  _ControlledDeleteFile(this.resolvePath, this.deleteFile);
  final Future<String> Function() resolvePath;
  final Future<FileSystemEntity> Function() deleteFile;

  @override
  Future<String> resolveSymbolicLinks() => resolvePath();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => deleteFile();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory cache;
  late File copy;
  late PathProviderPlatform originalProvider;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('temp-cleanup-retry-');
    cache = await Directory('${root.path}/cache').create();
    copy = await File('${cache.path}/photo.png').writeAsString('copy');
    originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPathProvider(cache.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalProvider;
    await root.delete(recursive: true);
  });

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
