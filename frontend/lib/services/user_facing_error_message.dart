import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'authenticated_api_client.dart';

// 파일명: user_facing_error_message.dart
// 역할: 기술 오류를 사용자가 이해하고 대응할 수 있는 안내 문구로 변환한다.

// 클래스명: UserFacingErrorContext
// 역할: 일반 요청과 약품 상세 검색의 오류 표시 맥락을 구분한다.
// 주요 책임:
// - 같은 서버 오류라도 약 검색에서는 이름 검토와 공공데이터 복구 안내를 선택하게 한다.
// 비고:
// - 파일명: user_facing_error_message.dart
enum UserFacingErrorContext { general, medicationLookup }

// 클래스명: UserFacingErrorMessage
// 역할: 기술 예외를 사용자가 이해할 수 있는 한국어·영어 오류 안내로 변환한다.
// 주요 책임:
// - 버전·네트워크·인증·과부하·약 검색 오류를 구분하고 처리 가능한 StateError 메시지는 보존한다.
class UserFacingErrorMessage {
  // 함수이름: UserFacingErrorMessage._
  // 함수역할: 공통 오류를 언어별 사용자 안내로 바꾸는 정적 API만 사용하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - UserFacingErrorMessage: 초기화된 인스턴스.
  const UserFacingErrorMessage._();

  // 함수이름: resolve
  // 함수역할: 예외 종류와 서버 상태 문구를 기준으로 네트워크, 인증, 검색, 외부 서비스 오류를 구분한다.
  // 매개변수:
  // - error (Object): 처리하거나 기록할 원래 실패 객체
  // - isEnglish (bool): 영어 표시 문구를 선택할지 여부
  // - context (UserFacingErrorContext): 오류 안내의 작업별 문구를 선택할 분류
  // 반환값:
  // - String: 예외 종류와 서버 상태 문구를 기준으로 네트워크, 인증, 검색, 외부 서비스 오류를 구분한다.
  static String resolve(
    Object error, {
    required bool isEnglish,
    UserFacingErrorContext context = UserFacingErrorContext.general,
  }) {
    if (error is ApiContractMismatchException) {
      return isEnglish
          ? 'This app version is not compatible with the server. Please update MedBuddy.'
          : '현재 앱 버전이 서버와 호환되지 않습니다. MedBuddy를 업데이트해주세요.';
    }
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

  // 함수이름: _containsAny
  // 함수역할: 정규화한 오류 문자열에 후보 오류 표식 중 하나라도 포함되어 있는지 확인한다.
  // 매개변수:
  // - source (String): 검색어 포함 여부를 검사할 원본 오류 텍스트
  // - candidates (List<String>): 일치 여부를 비교할 후보 목록
  // 반환값:
  // - bool: 정규화한 오류 문자열에 후보 오류 표식 중 하나라도 포함되어 있는지 확인한다.
  static bool _containsAny(String source, List<String> candidates) {
    return candidates.any(source.contains);
  }
}
