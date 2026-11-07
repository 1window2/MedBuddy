import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_response_parser.dart';
import 'authenticated_api_client.dart';

// 파일명: user_facing_error_message.dart
// 역할: 기술 오류를 사용자가 이해하고 대응할 수 있는 안내 문구로 변환한다.

// 클래스명: UserFacingErrorContext
// 역할: 일반 요청과 약품 상세 검색의 오류 안내 맥락을 구분한다.
// 주요 책임: 약 검색에서 이름 검토·공공데이터 복구 안내를 별도로 선택하게 한다.
// 속성: general: 일반 요청; medicationLookup: 약품 상세 조회.
enum UserFacingErrorContext { general, medicationLookup }

// Class Name: _RequestFailureKind
// Role: Categorizes request failures for consistent localized user guidance.
// Responsibilities: Share message selection between typed API failures and legacy text-only failures.
// Attributes: Values distinguish identity/access/link issues, delays/quotas and medication/public-data/server availability.
enum _RequestFailureKind {
  signInExpired,
  accessDenied,
  linkEnded,
  linkCodeInvalid,
  linkCodeUsed,
  linkToSelf,
  delayed,
  busy,
  dailyQuotaUsed,
  sharedDailyBudgetUsed,
  medicationNotFound,
  publicDataUnavailable,
  serverUnavailable,
}

// Class Name: UserFacingErrorMessage
// Role: Converts technical failures into Korean or English user guidance.
// Responsibilities: Prioritize typed transport causes, recognize selected status/detail combinations and preserve appropriate user-facing state errors.
// Attributes: Static helpers and character-pattern constants; no instance state.
class UserFacingErrorMessage {
  // 함수이름: UserFacingErrorMessage._
  // 함수역할: 공통 오류를 언어별 사용자 안내로 바꾸는 정적 API만 사용하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - UserFacingErrorMessage: 초기화된 인스턴스.
  const UserFacingErrorMessage._();

  // Function Name: resolve
  // Description: Resolves typed causes first, then recognized API status/detail combinations and legacy text markers.
  // Parameters: error: Original failure; isEnglish: Display language; context: Operation-specific classification.
  // Returns: Localized guidance; selected Korean server details may be preserved, unknown API failures include status, and unsupported diagnostics fall back to a generic message.
  static String resolve(
    Object error, {
    required bool isEnglish,
    UserFacingErrorContext context = UserFacingErrorContext.general,
  }) {
    if (error is ApiRequestException) {
      final cause = error.cause;
      if (cause is StateError) {
        return resolve(cause, isEnglish: isEnglish, context: context);
      }
      if (cause != null) {
        // 전송 단계 실패는 원인 예외의 종류로만 구분하고 예외 문구는 검사하지 않는다.
        return _messageForTransportError(cause, isEnglish: isEnglish) ??
            _genericMessage(isEnglish);
      }
      // 서버 상세 문구에 섞인 숫자가 상태 코드로 오인되지 않도록 상태 코드만 본다.
      final kind =
          _kindForDetail(error.statusCode, error.detail) ??
          _kindForStatusCode(error.statusCode, context);
      if (kind != null) {
        return _messageForKind(kind, isEnglish: isEnglish);
      }
      // 한국어 detail은 서버가 사용자에게 보여 주려고 쓴 문구다(예: 저장 약 개수 한도). 영어 detail은
      // 개발자용 문구이므로 보여 주지 않고, 문의할 때 추적할 수 있도록 상태 코드만 함께 적는다.
      final detail = error.detail.trim();
      if (!isEnglish && _isKoreanSentence(detail)) {
        return detail;
      }
      return _genericMessageWithStatus(isEnglish, error.statusCode);
    }
    final transportMessage = _messageForTransportError(
      error,
      isEnglish: isEnglish,
    );
    if (transportMessage != null) {
      return transportMessage;
    }

    final normalized = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .toLowerCase();
    final kind = _kindForText(normalized, context);
    if (kind != null) {
      return _messageForKind(kind, isEnglish: isEnglish);
    }

    final originalMessage = error.toString().replaceFirst('Bad state: ', '');
    if (originalMessage.trim().isNotEmpty && error is StateError) {
      // 영어 StateError 문구는 개발자용 확인 문구다(예: 응답에 필요한 데이터가 없음). 한국어 화면에는
      // 그대로 보여 주지 않고 일반 안내로 바꾼다.
      if (!isEnglish && !_isKoreanSentence(originalMessage.trim())) {
        return _genericMessage(isEnglish);
      }
      return originalMessage;
    }
    return _genericMessage(isEnglish);
  }

  // Function Name: _messageForTransportError
  // Description: Maps recognized contract, timeout and network exception types without inspecting their messages.
  // Parameters: error: Transport or contract failure; isEnglish: Display language.
  // Returns: Localized guidance, or null for an unrecognized exception type.
  static String? _messageForTransportError(
    Object error, {
    required bool isEnglish,
  }) {
    if (error is ApiContractMismatchException) {
      return isEnglish
          ? 'This app version is not compatible with the server. Please update MedBuddy.'
          : '현재 앱 버전이 서버와 호환되지 않습니다. MedBuddy를 업데이트해주세요.';
    }
    if (error is TimeoutException) {
      return _messageForKind(_RequestFailureKind.delayed, isEnglish: isEnglish);
    }
    if (error is SocketException || error is http.ClientException) {
      return isEnglish
          ? 'Check your internet connection and try again.'
          : '인터넷 연결을 확인한 뒤 다시 시도해주세요.';
    }
    return null;
  }

  // 함수이름: _kindForStatusCode
  // 함수역할: HTTP 상태 코드만으로 안내 유형을 정한다. 403은 접근 거부 문구가 확정될 때까지 로그인 만료 안내를 유지한다.
  // 매개변수:
  // - statusCode (int?): 거부된 응답의 HTTP 상태 코드. 응답이 없으면 null
  // - context (UserFacingErrorContext): 오류 안내의 작업별 문구를 선택할 분류
  // 반환값:
  // - _RequestFailureKind?: 상태 코드에 대응하는 안내 유형. 전용 안내가 없는 코드와 null은 null.
  static final RegExp _hangul = RegExp(r'[가-힣]');
  static final RegExp _latin = RegExp(r'[A-Za-z]');

  // Function Name: _isKoreanSentence
  // Description: Uses a Hangul-to-Latin character ratio to identify predominantly Korean user-facing text.
  // Parameters: text: Candidate server message.
  // Returns: True only with at least one Hangul character and at least three times as many Hangul characters as Latin letters.
  static bool _isKoreanSentence(String text) {
    final hangul = _hangul.allMatches(text).length;
    final latin = _latin.allMatches(text).length;
    return hangul > 0 && hangul >= latin * 3;
  }

  // Function Name: _kindForDetail
  // Description: Recognizes status-and-detail combinations whose meaning is more specific than the status alone.
  // Parameters: statusCode: HTTP status; detail: Server explanation.
  // Returns: A quota or relationship-related failure kind, or null when no configured combination matches.
  static _RequestFailureKind? _kindForDetail(int? statusCode, String detail) {
    final text = detail.toLowerCase();
    if (statusCode == 429 && (text.contains('내일') || text.contains('오늘'))) {
      return _RequestFailureKind.dailyQuotaUsed;
    }
    if (statusCode == 503 && text.contains('병원 정보를 조회할 수 있는 횟수')) {
      return _RequestFailureKind.sharedDailyBudgetUsed;
    }
    if (statusCode == 400 && text.contains('cannot link to the same')) {
      return _RequestFailureKind.linkToSelf;
    }
    if ((statusCode == 400 || statusCode == 404) &&
        (text.contains('patient code is invalid') ||
            text.contains('patient code was not found'))) {
      return _RequestFailureKind.linkCodeInvalid;
    }
    if (statusCode == 409 && text.contains('patient code was already used')) {
      return _RequestFailureKind.linkCodeUsed;
    }
    if ((statusCode == 403 || statusCode == 404) &&
        (text.contains('patient-caregiver link') ||
            text.contains('linked patient was not found') ||
            text.contains('patient scope is not permitted'))) {
      return _RequestFailureKind.linkEnded;
    }
    return null;
  }

  // Function Name: _kindForStatusCode
  // Description: Classifies HTTP failures while distinguishing denied access from expired sign-in and medication-data outages from generic server errors.
  // Parameters: statusCode (int?) - response status, if known; context (UserFacingErrorContext) - operation-specific classification.
  // Returns: Matching failure kind or null for unrecognized/missing status; 404/502/503 have medication-lookup-specific meanings.
  static _RequestFailureKind? _kindForStatusCode(
    int? statusCode,
    UserFacingErrorContext context,
  ) {
    if (statusCode == null) {
      return null;
    }
    final isMedicationLookup =
        context == UserFacingErrorContext.medicationLookup;
    if (statusCode == 401) {
      return _RequestFailureKind.signInExpired;
    }
    // 403은 로그인 만료가 아니라 이 요청의 거절이므로 다시 로그인해도 해결되지 않는다.
    if (statusCode == 403) {
      return _RequestFailureKind.accessDenied;
    }
    if (statusCode == 408 || statusCode == 504) {
      return _RequestFailureKind.delayed;
    }
    if (statusCode == 429) {
      return _RequestFailureKind.busy;
    }
    if (isMedicationLookup && statusCode == 404) {
      return _RequestFailureKind.medicationNotFound;
    }
    if (isMedicationLookup && (statusCode == 502 || statusCode == 503)) {
      return _RequestFailureKind.publicDataUnavailable;
    }
    if (statusCode >= 500) {
      return _RequestFailureKind.serverUnavailable;
    }
    return null;
  }

  // Function Name: _kindForText
  // Description: Classifies legacy untyped failures from normalized status markers and keywords.
  // Parameters: normalized: Lowercase error text without the Bad state prefix; context: Operation category.
  // Returns: The first matching failure kind, or null; medication-specific rules apply only to medication lookup.
  static _RequestFailureKind? _kindForText(
    String normalized,
    UserFacingErrorContext context,
  ) {
    if (_containsAny(normalized, const ['401', 'unauthorized'])) {
      return _RequestFailureKind.signInExpired;
    }
    if (normalized.contains('patient-caregiver link')) {
      return _RequestFailureKind.linkEnded;
    }
    if (normalized.contains('403')) {
      return _RequestFailureKind.accessDenied;
    }
    if (_containsAny(normalized, const ['timeout', '408', '504'])) {
      return _RequestFailureKind.delayed;
    }
    if (_containsAny(normalized, const ['429', 'too many'])) {
      return _RequestFailureKind.busy;
    }
    if (context == UserFacingErrorContext.medicationLookup &&
        _containsAny(normalized, const ['not found', '찾지 못', '검색 결과', '404'])) {
      return _RequestFailureKind.medicationNotFound;
    }
    if (context == UserFacingErrorContext.medicationLookup &&
        _containsAny(normalized, const [
          '공공데이터',
          'external',
          'upstream',
          '502',
          '503',
        ])) {
      return _RequestFailureKind.publicDataUnavailable;
    }
    if (_containsAny(normalized, const ['500', '502', '503'])) {
      return _RequestFailureKind.serverUnavailable;
    }
    return null;
  }

  // Function Name: _messageForKind
  // Description: Chooses actionable Korean or English guidance for a classified request failure.
  // Parameters: kind: Resolved failure category; isEnglish: Display language.
  // Returns: The corresponding localized message.
  static String _messageForKind(
    _RequestFailureKind kind, {
    required bool isEnglish,
  }) {
    return switch (kind) {
      _RequestFailureKind.signInExpired =>
        isEnglish
            ? 'Your sign-in has expired. Please sign in again.'
            : '로그인 정보가 만료되었습니다. 다시 로그인해주세요.',
      _RequestFailureKind.accessDenied =>
        isEnglish
            ? 'This request is not allowed. Check the patient/caregiver link and try again.'
            : '이 요청을 처리할 수 없습니다. 환자·보호자 연동 상태를 확인해주세요.',
      _RequestFailureKind.linkEnded =>
        isEnglish
            ? 'The patient/caregiver link has ended, so this information is no longer available.'
            : '환자·보호자 연동이 해제되어 이 정보를 더 이상 볼 수 없습니다.',
      _RequestFailureKind.linkCodeInvalid =>
        isEnglish
            ? 'The code is wrong or has expired. Ask the patient for a new code.'
            : '코드가 맞지 않거나 만료되었습니다. 환자에게 새 코드를 받아 주세요.',
      _RequestFailureKind.linkCodeUsed =>
        isEnglish
            ? 'This code has already been used. Ask the patient for a new code.'
            : '이미 사용한 코드입니다. 환자에게 새 코드를 받아 주세요.',
      _RequestFailureKind.linkToSelf =>
        isEnglish
            ? 'You cannot link to your own account.'
            : '내 계정과는 연동할 수 없습니다.',
      _RequestFailureKind.dailyQuotaUsed =>
        isEnglish
            ? "You have used today's limit for this feature. Please try again tomorrow."
            : '오늘 사용할 수 있는 횟수를 모두 사용했습니다. 내일 다시 시도해주세요.',
      _RequestFailureKind.sharedDailyBudgetUsed =>
        isEnglish
            ? "Today's hospital lookups are used up. Please try again tomorrow."
            : '오늘 병원 정보 조회 가능 횟수를 모두 사용했습니다. 내일 다시 시도해주세요.',
      _RequestFailureKind.delayed =>
        isEnglish
            ? 'The response is taking longer than expected. Please try again shortly.'
            : '응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.',
      _RequestFailureKind.busy =>
        isEnglish
            ? 'There are many requests right now. Please try again shortly.'
            : '현재 요청이 많습니다. 잠시 후 다시 시도해주세요.',
      _RequestFailureKind.medicationNotFound =>
        isEnglish
            ? 'No matching medication was found. Review the OCR medication name.'
            : '일치하는 약 정보를 찾지 못했습니다. OCR 약 이름을 확인해주세요.',
      _RequestFailureKind.publicDataUnavailable =>
        isEnglish
            ? 'The public medication data service is temporarily unavailable.'
            : '공공데이터 약품 정보 서비스가 일시적으로 응답하지 않습니다.',
      _RequestFailureKind.serverUnavailable =>
        isEnglish
            ? 'The MedBuddy server is temporarily unavailable. Please try again shortly.'
            : 'MedBuddy 서버가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도해주세요.',
    };
  }

  // Function Name: _genericMessageWithStatus
  // Description: Adds an optional HTTP status to generic localized retry guidance without exposing diagnostic text.
  // Parameters: isEnglish: Display language; statusCode: Known HTTP status, or null.
  // Returns: The generic message with a parenthesized status only when supplied.
  static String _genericMessageWithStatus(bool isEnglish, int? statusCode) {
    final generic = _genericMessage(isEnglish);
    return statusCode == null ? generic : '$generic ($statusCode)';
  }

  // Function Name: _genericMessage
  // Description: Supplies a retry suggestion without exposing diagnostic or server-provided details.
  // Parameters: isEnglish (bool) - whether to use English instead of Korean.
  // Returns: The fixed localized fallback error message.
  static String _genericMessage(bool isEnglish) {
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
