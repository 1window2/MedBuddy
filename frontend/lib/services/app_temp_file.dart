import 'dart:io';

import 'package:path_provider/path_provider.dart';

// File Name: app_temp_file.dart
// Role: Deletes image copies the app or its image picker left in the app temporary directory.

// Function Name: deleteAppTempFile
// Description: Deletes a file only when its canonical location is inside the app temporary directory, so a user's original photo or any other file outside it is never touched. Never throws.
// Parameters:
// - path (String): Path of the picked, captured or cropped copy to remove.
// Returns:
// - True when the file was inside the temporary directory and was deleted; false for a missing file, a directory, a location outside the temporary directory or any failure.
Future<bool> deleteAppTempFile(String path) async {
  if (path.trim().isEmpty) {
    return false;
  }
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
  } catch (_) {
    // Cleanup is best effort: a missing file, an IO error or an unavailable path provider leaves the file in place.
    return false;
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
