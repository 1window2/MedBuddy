// File Name: app_temp_file_test.dart
// Role: Regression coverage for deleting picked and cropped image copies only inside the app
//   temporary directory.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/app_temp_file.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Class Name: _TemporaryPathProvider
// Role: Test path provider that reports a chosen directory as the app temporary directory.
// Responsibilities:
// - Replace the platform channel so the temporary directory is a folder the test controls.
// - Simulate an unavailable path provider when no directory is given.
// Attributes:
// - temporaryPath (String?): Directory reported as the temporary directory; null makes the lookup fail.
class _TemporaryPathProvider extends PathProviderPlatform {
  final String? temporaryPath;

  // Function Name: _TemporaryPathProvider
  // Description:
  // - Keep the directory to report as the app temporary directory.
  // Parameters:
  // - temporaryPath (String?): Directory to report, or null to fail the lookup.
  // Returns:
  // - _TemporaryPathProvider: the initialized instance.
  _TemporaryPathProvider(this.temporaryPath);

  // Function Name: getTemporaryPath
  // Description:
  // - Report the configured temporary directory, or fail like a missing platform plugin.
  // Parameters:
  // - None.
  // Returns:
  // - The configured directory path; throws StateError when none was configured.
  @override
  Future<String?> getTemporaryPath() async {
    final path = temporaryPath;
    if (path == null) {
      throw StateError('path provider unavailable');
    }
    return path;
  }
}

// Function Name: main
// Description:
// - Register regression cases for deleting image copies only inside the app temporary directory.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory temporaryDirectory;
  late Directory outsideDirectory;
  late PathProviderPlatform originalProvider;

  // Function Name: setUp callback
  // Description:
  // - Create a temporary directory and a sibling directory outside it, and report the first one
  //   as the app temporary directory.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the directories exist and the provider is replaced.
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('medbuddy-temp-file-test-');
    temporaryDirectory = await Directory('${sandbox.path}/cache').create();
    outsideDirectory = await Directory('${sandbox.path}/cache-gallery').create();
    originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPathProvider(
      temporaryDirectory.path,
    );
  });

  // Function Name: tearDown callback
  // Description:
  // - Restore the path provider and remove the directories of the finished case.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the sandbox is deleted.
  tearDown(() async {
    PathProviderPlatform.instance = originalProvider;
    await sandbox.delete(recursive: true);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a copy directly in the temporary directory and one in a picker
  //   subdirectory are deleted and reported as deleted.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('deletes a file inside the temporary directory', () async {
    final direct = File('${temporaryDirectory.path}/scaled_photo.jpg');
    await direct.writeAsString('copy');
    final pickerDirectory = await Directory(
      '${temporaryDirectory.path}/3f2a',
    ).create();
    final nested = File('${pickerDirectory.path}/photo.jpg');
    await nested.writeAsString('copy');

    expect(await deleteAppTempFile(direct.path), isTrue);
    expect(await deleteAppTempFile(nested.path), isTrue);

    expect(await direct.exists(), isFalse);
    expect(await nested.exists(), isFalse);
    expect(await pickerDirectory.exists(), isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a file outside the temporary directory is kept, including one in a
  //   sibling directory whose name starts with the temporary directory name and one reached
  //   through a relative path that leaves the directory.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('keeps a file outside the temporary directory', () async {
    final original = File('${outsideDirectory.path}/original.jpg');
    await original.writeAsString('original');

    expect(await deleteAppTempFile(original.path), isFalse);
    expect(
      await deleteAppTempFile(
        '${temporaryDirectory.path}/../cache-gallery/original.jpg',
      ),
      isFalse,
    );

    expect(await original.readAsString(), 'original');
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a link placed in the temporary directory does not lead the deletion to
  //   its target outside; neither the target nor the link is removed.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('does not follow a link out of the temporary directory', () async {
    final original = File('${outsideDirectory.path}/original.jpg');
    await original.writeAsString('original');
    final link = await Link(
      '${temporaryDirectory.path}/link.jpg',
    ).create(original.path);

    expect(await deleteAppTempFile(link.path), isFalse);

    expect(await original.readAsString(), 'original');
    expect(await link.exists(), isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a missing file, an empty path and a directory are reported as not
  //   deleted without throwing, and the directory is kept.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('returns false for a missing file, an empty path and a directory', () async {
    final pickerDirectory = await Directory(
      '${temporaryDirectory.path}/3f2a',
    ).create();

    expect(
      await deleteAppTempFile('${temporaryDirectory.path}/missing.jpg'),
      isFalse,
    );
    expect(await deleteAppTempFile(''), isFalse);
    expect(await deleteAppTempFile('  '), isFalse);
    expect(await deleteAppTempFile(pickerDirectory.path), isFalse);

    expect(await pickerDirectory.exists(), isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: when the temporary directory cannot be resolved the file is kept and
  //   the failure is reported as not deleted instead of being thrown.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('keeps the file when the temporary directory is unavailable', () async {
    final copy = File('${temporaryDirectory.path}/photo.jpg');
    await copy.writeAsString('copy');
    PathProviderPlatform.instance = _TemporaryPathProvider(null);

    expect(await deleteAppTempFile(copy.path), isFalse);

    expect(await copy.exists(), isTrue);
  });
}
