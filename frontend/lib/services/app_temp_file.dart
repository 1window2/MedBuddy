import 'dart:io';

import 'package:path_provider/path_provider.dart';

// File Name: app_temp_file.dart
// Role: Deletes image copies the app or its image picker left in the app temporary directory.

// 함수이름: deleteAppTempFile
// 함수역할: 실제 경로가 앱 임시 폴더 안의 파일일 때만 삭제하고 Windows 공유 잠금 오류는 최대 세 번 재시도한다.
// 매개변수: path (String): 삭제 후보 경로; 빈 값·폴더·앱 임시 영역 밖의 파일은 거절한다.
// 반환값: Future<bool>: 삭제 성공이면 true; 경로 검증 실패나 처리되지 않은 파일 오류이면 false.
Future<bool> deleteAppTempFile(String path) async {
  if (path.trim().isEmpty) {
    return false;
  }
  for (var attempt = 0; ; attempt += 1) {
    try {
      // Links are resolved first so that a link cannot point the deletion at a file outside the directory.
      final canonicalPath = await File(path).resolveSymbolicLinks();
      if (!await FileSystemEntity.isFile(canonicalPath)) {
        return false;
      }
      for (final directoryPath in await _appTempDirectoryPaths()) {
        if (_isInsideDirectory(canonicalPath, directoryPath)) {
          await File(canonicalPath).delete();
          return true;
        }
      }
      return false;
    } on FileSystemException catch (error) {
      // Windows 이미지 디코더가 파일을 잠시 잡고 있으면 제한적으로 재시도한다.
      // 재시도마다 원래 경로와 임시 폴더를 다시 확인해 외부 파일은 지우지 않는다.
      if (!Platform.isWindows ||
          !const [32, 33].contains(error.osError?.errorCode) ||
          attempt >= 3) {
        return false;
      }
      await Future<void>.delayed(Duration(milliseconds: 100 * (1 << attempt)));
    } catch (_) {
      // Cleanup is best effort: a missing file, an IO error or an unavailable path provider leaves the file in place.
      return false;
    }
  }
}

// Function Name: _appTempDirectoryPaths
// Description: Lists the canonical directories that hold app-owned temporary files: the path-provider temporary directory (the cache directory the Android image picker writes to) and, on iOS, the system temporary directory its image picker uses.
// Parameters:
// - None.
// Returns:
// - Canonical paths of the temporary directories that exist.
Future<List<String>> _appTempDirectoryPaths() async {
  final directories = <Directory>[
    await getTemporaryDirectory(),
    if (Platform.isIOS) Directory.systemTemp,
  ];
  final directoryPaths = <String>[];
  for (final directory in directories) {
    if (await directory.exists()) {
      directoryPaths.add(await directory.resolveSymbolicLinks());
    }
  }
  return directoryPaths;
}

// Function Name: _isInsideDirectory
// Description: Checks that a canonical file path lies below a canonical directory path, comparing whole path segments.
// Parameters:
// - filePath (String): Canonical path of the file.
// - directoryPath (String): Canonical path of the directory.
// Returns:
// - True when the file is in the directory or one of its subdirectories.
bool _isInsideDirectory(String filePath, String directoryPath) {
  final separator = Platform.pathSeparator;
  final prefix = directoryPath.endsWith(separator)
      ? directoryPath
      : '$directoryPath$separator';
  return filePath.startsWith(prefix);
}
