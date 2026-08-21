import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

// 파일명: user_facing_error_message.dart
// 역할: 기술 오류를 사용자가 이해하고 대응할 수 있는 안내 문구로 변환한다.

enum UserFacingErrorContext { general, medicationLookup }

class UserFacingErrorMessage {
  const UserFacingErrorMessage._();

  // 함수명: resolve
  // 역할:
  // - 예외 종류와 서버 상태 문구를 기준으로 네트워크, 인증, 검색, 외부 서비스 오류를 구분한다.
  static String resolve(
    Object error, {
    required bool isEnglish,
    UserFacingErrorContext context = UserFacingErrorContext.general,
  }) {
    if (error is TimeoutException) {
      return isEnglish
          ? 'The response is taking longer than expected. Please try again shortly.'
          : '응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.';
    }
    if (error is SocketException || error is http.ClientException) {
      return isEnglish
          ? 'Check your internet connection and try again.'
          : '인터넷 연결을 확인한 뒤 다시 시도해주세요.';
    }

    final normalized = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .toLowerCase();
    if (_containsAny(normalized, const ['401', '403', 'unauthorized'])) {
      return isEnglish
          ? 'Your sign-in has expired. Please sign in again.'
          : '로그인 정보가 만료되었습니다. 다시 로그인해주세요.';
    }
    if (_containsAny(normalized, const ['timeout', '408', '504'])) {
      return isEnglish
          ? 'The response is taking longer than expected. Please try again shortly.'
          : '응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.';
    }
    if (_containsAny(normalized, const ['429', 'too many'])) {
      return isEnglish
          ? 'There are many requests right now. Please try again shortly.'
          : '현재 요청이 많습니다. 잠시 후 다시 시도해주세요.';
    }
    if (context == UserFacingErrorContext.medicationLookup &&
        _containsAny(normalized, const ['not found', '찾지 못', '검색 결과', '404'])) {
      return isEnglish
          ? 'No matching medication was found. Review the OCR medication name.'
          : '일치하는 약 정보를 찾지 못했습니다. OCR 약 이름을 확인해주세요.';
    }
    if (context == UserFacingErrorContext.medicationLookup &&
        _containsAny(normalized, const [
          '공공데이터',
          'external',
          'upstream',
          '502',
          '503',
        ])) {
      return isEnglish
          ? 'The public medication data service is temporarily unavailable.'
          : '공공데이터 약품 정보 서비스가 일시적으로 응답하지 않습니다.';
    }
    if (_containsAny(normalized, const ['500', '502', '503'])) {
      return isEnglish
          ? 'The MedBuddy server is temporarily unavailable. Please try again shortly.'
          : 'MedBuddy 서버가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도해주세요.';
    }

    final originalMessage = error.toString().replaceFirst('Bad state: ', '');
    if (originalMessage.trim().isNotEmpty && error is StateError) {
      return originalMessage;
    }
    return isEnglish
        ? 'Something went wrong. Please try again.'
        : '요청을 처리하지 못했습니다. 다시 시도해주세요.';
  }

  static bool _containsAny(String source, List<String> candidates) {
    return candidates.any(source.contains);
  }
}
