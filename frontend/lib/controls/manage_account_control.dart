import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';

// 파일명: manage_account_control.dart
// 역할: 사용자 데이터 전체 삭제 요청과 기기 캐시 정리를 담당한다.

// 클래스명: ManageAccount
// 역할: 서버 계정 데이터와 로컬 캐시의 삭제 순서를 한곳에서 관리한다.
class ManageAccount {
  final String userHash;
  final http.Client client;

  const ManageAccount({required this.userHash, required this.client});

  // 함수명: deleteAccountData
  // 역할:
  // - 인증된 사용자 범위의 서버 데이터를 먼저 삭제한 뒤 기기 캐시를 비운다.
  // - 서버 삭제가 실패하면 로컬 상태를 보존해 사용자가 다시 시도할 수 있게 한다.
  Future<void> deleteAccountData() async {
    final response = await client
        .delete(Uri.parse(ApiConfig.authUrl('/account-data')))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('계정 데이터를 삭제하지 못했습니다.');
    }
    final normalizedUserHash = userHash.trim();
    if (normalizedUserHash.isEmpty) {
      throw StateError('삭제할 사용자 범위가 없습니다.');
    }
    final preferences = await SharedPreferences.getInstance();
    final userScopedKeys = preferences
        .getKeys()
        .where((key) => key.contains(normalizedUserHash))
        .toList(growable: false);
    for (final key in userScopedKeys) {
      await preferences.remove(key);
    }
  }
}
