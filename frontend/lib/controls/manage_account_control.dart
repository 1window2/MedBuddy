import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';

// 파일명: manage_account_control.dart
// 역할: 사용자 데이터 전체 삭제 요청과 기기 캐시 정리를 담당한다.

// Class Name: ManageAccount
// Role: Coordinates deletion of server account data and user-scoped local preferences.
// Responsibilities:
// - Delete authenticated backend data first and retain local state when the server rejects deletion.
// Attributes:
// - userHash (String): Current user hash defining ownership, display, or persistence scope.
// - client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
class ManageAccount {
  final String userHash;
  final http.Client client;

  // Function Name: ManageAccount
  // Description: Binds authenticated account deletion and subsequent local-cache cleanup to the supplied user scope and HTTP client.
  // Parameters:
  // - userHash (String): Current user hash defining ownership, display, or persistence scope.
  // - client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - ManageAccount: the initialized instance.
  const ManageAccount({required this.userHash, required this.client});

  // Function Name: deleteAccountData
  // Description: Deletes authenticated server account data, then removes preference keys containing the nonempty current user hash; server failure leaves the cache untouched.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
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
        .where(/* Function Name: where callback
         * Description: Selects local preference keys containing the normalized account hash for account cleanup.
         * Parameters:
         * - key (String): Flutter widget identity key.
         * Returns:
         * - Whether the key belongs to the account's cleanup set.
         */(key) => key.contains(normalizedUserHash))
        .toList(growable: false);
    for (final key in userScopedKeys) {
      await preferences.remove(key);
    }
  }
}
