// File Name: authentication_control.dart
// Role: Coordinates Firebase identity, SMS challenges, and authenticated backend sessions.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../entities/auth_session_entity.dart';
import '../entities/authentication_gate_state_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/auth_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/backend_session_failure.dart';
import '../services/firebase_runtime_service.dart';
import '../services/user_facing_error_message.dart';
import 'app_language_control.dart';

// Class Name: SmsChallengePurpose
// Role: Distinguishes phone sign-in, MFA sign-in, and MFA enrollment challenges.
// Responsibilities:
// - Select the credential completion path for an entered SMS code.
enum SmsChallengePurpose { phoneSignIn, mfaSignIn, mfaEnrollment }

// Class Name: AuthenticationErrorCode
// Role: Identifies each authentication failure independently of the language it is shown in.
// Responsibilities:
// - Hold the English and Korean guidance for one failure so every screen resolves the same code to the same sentence.
// Attributes:
// - english (String): English guidance; also the text exposed by AuthenticationControl.errorMessage.
// - korean (String): Korean guidance for the same failure.
enum AuthenticationErrorCode {
  configuration(
    'MedBuddy authentication is not configured correctly.',
    '로그인 설정에 문제가 있습니다. 관리자에게 문의해 주세요.',
  ),
  initialization(
    'MedBuddy could not initialize its secure services. Check the network and retry.',
    '로그인 서비스를 시작하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
  ),
  stateRefreshFailed(
    'Authentication state could not be refreshed.',
    '로그인 상태를 확인하지 못했습니다. 다시 시도해 주세요.',
  ),
  firebaseUnavailable(
    'Firebase authentication is unavailable.',
    '로그인 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.',
  ),
  operationInProgress(
    'Another authentication request is already running.',
    '다른 인증 요청을 처리하고 있습니다. 잠시 후 다시 시도해 주세요.',
  ),
  requestFailed(
    'Authentication request failed. Please try again.',
    '인증 요청을 처리하지 못했습니다. 다시 시도해 주세요.',
  ),
  timeout(
    'Authentication timed out. Check the network and try again.',
    '연결 시간이 초과되었습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
  ),
  sessionExpired(
    'Your secure session expired. Please sign in again.',
    '로그인 정보가 만료되었습니다. 다시 로그인해 주세요.',
  ),
  retryRequiresSignIn(
    'Sign in before retrying the secure session.',
    '보안 세션을 다시 연결하려면 먼저 로그인해 주세요.',
  ),
  noSignedInUser(
    'No signed-in user is available.',
    '로그인 정보가 없습니다. 다시 로그인해 주세요.',
  ),
  invalidEmail('Enter a valid email address.', '올바른 이메일 주소를 입력해 주세요.'),
  emailRequired('Enter your email address first.', '먼저 이메일 주소를 입력해 주세요.'),
  wrongCredentials(
    'The email or password is incorrect.',
    '이메일 또는 비밀번호가 올바르지 않습니다.',
  ),
  emailAlreadyInUse(
    'An account already uses this email address.',
    '이미 가입된 이메일입니다. 로그인하거나 비밀번호를 재설정해 주세요.',
  ),
  credentialAlreadyInUse(
    'This sign-in method belongs to another account. Sign out first to use it.',
    '다른 계정에 연결된 로그인 방법입니다. 먼저 로그아웃해 주세요.',
  ),
  weakPassword(
    'Use a stronger password with at least six characters.',
    '비밀번호는 6자 이상으로 설정해 주세요.',
  ),
  tooManyRequests(
    'Too many attempts. Please wait and try again.',
    '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
  ),
  network(
    'Check your network connection and try again.',
    '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
  ),
  signInMethodDisabled(
    'This sign-in method is not enabled yet.',
    '아직 사용할 수 없는 로그인 방법입니다.',
  ),
  emailVerificationPending(
    'Email verification is not complete yet. Open the link in your email, then try again.',
    '아직 인증되지 않았어요. 메일의 인증 링크를 누른 뒤 다시 확인해 주세요.',
  ),
  googleSignInIncomplete(
    'Google sign-in was not completed.',
    'Google 로그인을 완료하지 못했습니다. 다시 시도해 주세요.',
  ),
  googleSignInCanceled('Google sign-in was canceled.', 'Google 로그인을 취소했습니다.'),
  googleIdentityTokenMissing(
    'Google did not return an identity token.',
    'Google에서 로그인 정보를 받지 못했습니다. 다시 시도해 주세요.',
  ),
  phoneAuthenticationUnavailable(
    'Phone authentication is unavailable in this beta build.',
    '현재 버전에서는 문자 인증을 사용할 수 없습니다.',
  ),
  smsVerificationUnavailable(
    'SMS verification is unavailable in this beta build.',
    '현재 버전에서는 문자 인증을 사용할 수 없습니다.',
  ),
  internationalPhoneNumberRequired(
    'Use an international phone number such as +821012345678.',
    '국가번호를 포함한 올바른 전화번호를 입력해 주세요.',
  ),
  invalidPhoneNumber(
    'Enter a valid international phone number.',
    '국가번호를 포함한 올바른 전화번호를 입력해 주세요.',
  ),
  smsCodeNotRequested('Request a new SMS code first.', '먼저 문자 인증번호를 요청해 주세요.'),
  smsCodeIncomplete(
    'Enter the six-digit SMS code.',
    '문자로 받은 6자리 인증번호를 입력해 주세요.',
  ),
  smsCodeIncorrect(
    'The SMS verification code is incorrect.',
    '문자 인증번호가 올바르지 않습니다.',
  ),
  smsQuotaExceeded(
    'The SMS quota is exhausted. Try again later.',
    '문자 발송 한도를 초과했습니다. 나중에 다시 시도해 주세요.',
  ),
  mfaRecentSignInRequired(
    'Sign out and sign in again before changing MFA.',
    '인증 설정을 바꾸려면 로그아웃한 뒤 다시 로그인해 주세요.',
  ),
  mfaVerifiedEmailRequired(
    'Sign in with a verified email account before enabling MFA.',
    '먼저 이메일 인증을 완료한 계정으로 로그인해 주세요.',
  ),
  mfaFactorUnsupported(
    'No supported SMS second factor is available.',
    '사용할 수 있는 추가 문자 인증 방법이 없습니다.',
  ),
  mfaSignInExpired(
    'The MFA sign-in session has expired.',
    '추가 인증 로그인 시간이 만료되었습니다. 다시 로그인해 주세요.',
  ),
  mfaEnrollmentExpired(
    'The MFA enrollment session has expired.',
    '추가 인증 등록 시간이 만료되었습니다. 다시 시도해 주세요.',
  ),
  deletionRequiresSignIn(
    'Sign in before deleting this account.',
    '계정을 삭제하려면 먼저 로그인해 주세요.',
  ),
  deletionRequiresRecentSignIn(
    'For security, sign out and sign in again before deleting this account.',
    '보안을 위해 로그아웃한 뒤 다시 로그인하고 계정을 삭제해 주세요.',
  );

  // Function Name: AuthenticationErrorCode
  // Description: Binds one failure code to its English and Korean guidance.
  // Parameters:
  // - english (String): English guidance for the failure.
  // - korean (String): Korean guidance for the failure.
  // Returns:
  // - AuthenticationErrorCode: the initialized constant.
  const AuthenticationErrorCode(this.english, this.korean);

  final String english;
  final String korean;

  // Function Name: messageFor
  // Description: Selects the guidance for the language currently shown on screen.
  // Parameters:
  // - isEnglish (bool): Whether to choose the English display string.
  // Returns:
  // - String: English or Korean guidance for this failure.
  String messageFor(bool isEnglish) => isEnglish ? english : korean;
}

// Class Name: AuthenticationStateError
// Role: Carries an authentication failure code through callers that handle StateError.
// Responsibilities:
// - Keep the English sentence as the StateError message while letting a screen localize the failure by code.
// Attributes:
// - code (AuthenticationErrorCode): Language-independent identity of the failure.
class AuthenticationStateError extends StateError {
  final AuthenticationErrorCode code;

  // Function Name: AuthenticationStateError
  // Description: Creates a StateError whose message is the English guidance of the supplied code.
  // Parameters:
  // - code (AuthenticationErrorCode): Language-independent identity of the failure.
  // Returns:
  // - AuthenticationStateError: the initialized instance.
  AuthenticationStateError(this.code) : super(code.english);

  // Function Name: messageFor
  // Description: Resolves this failure in the language currently shown on screen.
  // Parameters:
  // - isEnglish (bool): Whether to choose the English display string.
  // Returns:
  // - String: English or Korean guidance for this failure.
  String messageFor(bool isEnglish) => code.messageFor(isEnglish);
}

// Class Name: _IdentityFailureKind
// Role: Records what a failed Firebase identity call says about the account itself.
// Responsibilities:
// - Separate a rejected identity from a call that could not be completed and from a result that needs a second check.
enum _IdentityFailureKind { rejected, unavailable, ambiguous }

// Class Name: _SessionFailureKind
// Role: Records how a failed backend session synchronization must be handled.
// Responsibilities:
// - rejected: the identity is no longer valid, so the provider session is signed out.
// - refused: the server answered with a verdict that ends the MedBuddy session.
// - inconclusive: no verdict was obtained, so an established session for the same identity is kept.
enum _SessionFailureKind { rejected, refused, inconclusive }

// Class Name: _IdTokenFailure
// Role: Marks a synchronization that stopped because the Firebase ID token could not be read.
// Responsibilities:
// - Preserve the original SDK failure so it can be classified instead of being read as a generic outage.
// Attributes:
// - cause (Object): Failure raised by the Firebase SDK, or a timeout.
class _IdTokenFailure implements Exception {
  final Object cause;

  // Function Name: _IdTokenFailure
  // Description: Wraps the failure raised while reading the current user's ID token.
  // Parameters:
  // - cause (Object): Failure raised by the Firebase SDK, or a timeout.
  // Returns:
  // - _IdTokenFailure: the initialized instance.
  const _IdTokenFailure(this.cause);
}

// Class Name: _PendingHandshake
// Role: Describes the backend session request currently in flight.
// Responsibilities:
// - Let a second synchronization for the same identity and token reuse the request instead of sending another.
// Attributes:
// - subject (String): Firebase uid the request was sent for.
// - token (String): ID token the request was sent with.
// - result (Future<AuthSession>): Outcome shared by every synchronization that joins the request.
class _PendingHandshake {
  final String subject;
  final String token;
  final Future<AuthSession> result;

  // Function Name: _PendingHandshake
  // Description: Records the identity, token, and shared outcome of one backend session request.
  // Parameters:
  // - subject (String): Firebase uid the request was sent for.
  // - token (String): ID token the request was sent with.
  // - result (Future<AuthSession>): Outcome shared by every synchronization that joins the request.
  // Returns:
  // - _PendingHandshake: the initialized instance.
  const _PendingHandshake(this.subject, this.token, this.result);
}

// Function Name: _classifyIdentityFailure
// Description: Decides what a failed Firebase user call says about the account. Codes that mean the account or its refresh token is gone are rejected; network, quota, and timeout failures are unavailable; every other code is ambiguous because the Android plugin reports a rejected getIdToken call as `unknown`.
// Parameters:
// - error (Object): Failure raised by getIdToken or reload, or a timeout.
// Returns:
// - _IdentityFailureKind: rejected, unavailable, or ambiguous.
_IdentityFailureKind _classifyIdentityFailure(Object error) {
  if (error is TimeoutException) {
    return _IdentityFailureKind.unavailable;
  }
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'user-token-expired' ||
      'user-disabled' ||
      'user-not-found' ||
      'invalid-user-token' ||
      'no-current-user' => _IdentityFailureKind.rejected,
      'network-request-failed' ||
      'too-many-requests' ||
      'api-not-available' => _IdentityFailureKind.unavailable,
      _ => _IdentityFailureKind.ambiguous,
    };
  }
  return _IdentityFailureKind.ambiguous;
}

// 클래스명: AuthenticationControl
// 역할: Firebase 신원과 백엔드 세션 교환을 조정해 인증 게이트 상태를 유지한다.
// 주요 책임:
// - 인증 작업을 직렬화하고 복구 가능한 오류를 노출하며 공급자 로그아웃 전에 개인정보 관련 정리를 완료한다.
// 속성:
// - apiClient (AuthenticatedApiClient): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
// - _errorMessage (String?): 실패 상태에 사용할 사용자 안내문
class AuthenticationControl extends ChangeNotifier
    implements AuthenticationGateState {
  static const Duration _backendSessionTimeout = Duration(seconds: 20);
  static const Duration _authenticationOperationTimeout = Duration(seconds: 30);
  static const Duration _mfaStatusTimeout = Duration(seconds: 10);
  static const Duration _idTokenTimeout = Duration(seconds: 10);
  static const Duration _identityProbeTimeout = Duration(seconds: 10);
  // Same steps as the sign-in screen's foreground recovery; bounded so a long
  // outage does not keep polling. The next token refresh starts a new series.
  static const List<Duration> _sessionResyncDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
  ];

  FirebaseAuth? _firebaseAuth;
  StreamSubscription<User?>? _authSubscription;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInInitialized = false;
  late final AuthenticatedApiClient apiClient;
  int _sessionGeneration = 0;
  Future<void>? _latestSynchronization;
  int _latestSynchronizationGeneration = 0;
  _PendingHandshake? _pendingHandshake;
  // Firebase uid the current session was established for; null without one.
  String? _sessionSubject;
  Timer? _sessionResyncTimer;
  int _sessionResyncAttempts = 0;
  String? _deletedFirebaseSubject;
  Future<void> Function()? _beforeSignOut;
  bool _isInvalidatingUnauthorizedSession = false;

  bool _isInitializing = true;
  // Function Name: isInitializing
  // Description: Reports whether secure-service bootstrap is still pending for the authentication gate.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether secure-service bootstrap is still pending for the authentication gate.
  @override
  bool get isInitializing => _isInitializing;

  bool _isBusy = false;
  // Function Name: isBusy
  // Description: Reports whether an authentication operation currently holds the single-operation guard.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether an authentication operation currently holds the single-operation guard.
  bool get isBusy => _isBusy;

  AuthSession? _session;
  // Function Name: session
  // Description: Exposes the synchronized MedBuddy session, or null while signed out or awaiting a valid backend handshake.
  // Parameters:
  // - None.
  // Returns:
  // - AuthSession?: The synchronized MedBuddy session, or null while signed out or awaiting a valid backend handshake.
  AuthSession? get session => _session;

  // Function Name: isAuthenticated
  // Description: Reports whether a MedBuddy session is available to open the authenticated application.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether a MedBuddy session is available to open the authenticated application.
  @override
  bool get isAuthenticated => _session != null;

  String? _signedInEmail;
  // Function Name: signedInEmail
  // Description: Exposes the email cached during Firebase identity synchronization.
  // Parameters:
  // - None.
  // Returns:
  // - String?: The email cached during Firebase identity synchronization.
  String? get signedInEmail => _signedInEmail;
  // 함수이름: signedInDisplayName
  // 함수역할: 공급자가 제공한 Firebase 표시 이름의 앞뒤 공백을 정리해 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String?: 공급자가 제공한 Firebase 표시 이름의 앞뒤 공백을 정리해 제공한다.
  String? get signedInDisplayName =>
      _firebaseAuth?.currentUser?.displayName?.trim();
  // 함수이름: signedInPhoneNumber
  // 함수역할: 현재 Firebase 신원에 연결된 전화번호의 앞뒤 공백을 정리해 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String?: 현재 Firebase 신원에 연결된 전화번호의 앞뒤 공백을 정리해 제공한다.
  String? get signedInPhoneNumber =>
      _firebaseAuth?.currentUser?.phoneNumber?.trim();

  // Function Name: isAnonymous
  // Description: Identifies a Firebase guest account that can be upgraded by linking credentials.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Identifies a Firebase guest account that can be upgraded by linking credentials.
  bool get isAnonymous => _firebaseAuth?.currentUser?.isAnonymous == true;

  bool _emailVerificationRequired = false;
  // Function Name: emailVerificationRequired
  // Description: Reports whether email verification is blocking creation of the backend session.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether email verification is blocking creation of the backend session.
  bool get emailVerificationRequired => _emailVerificationRequired;

  String? _errorMessage;
  // Function Name: errorMessage
  // Description: Exposes the latest user-facing authentication error, or null when cleared.
  // Parameters:
  // - None.
  // Returns:
  // - String?: User-facing guidance for the failure state.
  String? get errorMessage => _errorMessage;
  AuthenticationErrorCode? _errorCode;
  Object? _backendSessionError;

  // 함수이름: errorMessageForLanguage
  // 함수역할: 인증·서버 세션 오류를 현재 선택 언어로 표시하며, 언어를 바꾸어도 이미 발생한 오류를 다시 번역한다.
  // 매개변수:
  // - isEnglish (bool): 영어 표시 문구를 선택할지 여부
  // 반환값:
  // - String?: 서버 세션 연결 오류를 로그인 화면의 현재 언어에 맞는 안내로 변환한다. 버전 계약 불일치는 앱 업데이트가 필요하다는 구체적인 행동을 안내한다.
  String? errorMessageForLanguage({required bool isEnglish}) {
    if (_errorMessage == null) {
      return null;
    }
    final backendSessionError = _backendSessionError;
    if (backendSessionError != null) {
      return resolveBackendSessionError(
        backendSessionError,
        isEnglish: isEnglish,
      );
    }
    final errorCode = _errorCode;
    if (errorCode != null) {
      return errorCode.messageFor(isEnglish);
    }
    // 코드 없이 전달된 문구는 영어 원문만 알 수 있으므로 한국어 화면에는 일반 안내를 보여 준다.
    return isEnglish
        ? _errorMessage
        : AuthenticationErrorCode.requestFailed.korean;
  }

  // 함수이름: resolveBackendSessionError
  // 함수역할: 인증 handshake 실패 원인을 기술 문구 대신 사용자가 대응할 수 있는 문구로 바꾼다. 테스트와 로그인 UI가 동일한 변환 규칙을 공유한다.
  // 매개변수:
  // - error (Object): 처리하거나 기록할 원래 실패 객체
  // - isEnglish (bool): 영어 표시 문구를 선택할지 여부
  // 반환값:
  // - String: 인증 handshake 실패 원인을 기술 문구 대신 사용자가 대응할 수 있는 문구로 바꾼다. 테스트와 로그인 UI가 동일한 변환 규칙을 공유한다.
  static String resolveBackendSessionError(
    Object error, {
    required bool isEnglish,
  }) {
    if (error is ApiContractMismatchException) {
      return UserFacingErrorMessage.resolve(error, isEnglish: isEnglish);
    }
    return isEnglish
        ? 'The secure MedBuddy server session could not be established.'
        : 'MedBuddy 보안 서버 세션을 연결하지 못했습니다.';
  }

  bool _configurationFailed = false;
  // Function Name: configurationFailed
  // Description: Reports a configuration-validation failure that cannot be resolved by retrying startup.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Reports a configuration-validation failure that cannot be resolved by retrying startup.
  bool get configurationFailed => _configurationFailed;

  bool _initializationFailed = false;
  // Function Name: initializationFailed
  // Description: Reports a secure-service startup failure that allows the initialization retry flow.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Reports a secure-service startup failure that allows the initialization retry flow.
  bool get initializationFailed => _initializationFailed;
  // Function Name: phoneAuthenticationEnabled
  // Description: Exposes the build-time switch controlling phone sign-in and SMS MFA availability.
  // Parameters:
  // - None.
  // Returns:
  // - bool: The build-time switch controlling phone sign-in and SMS MFA availability.
  bool get phoneAuthenticationEnabled => AuthConfig.phoneAuthenticationEnabled;

  // Function Name: canRetryBackendSession
  // Description: Allows a handshake retry only for a present, email-eligible Firebase user without a session or initialization failure.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Allows a handshake retry only for a present, email-eligible Firebase user without a session or initialization failure.
  bool get canRetryBackendSession {
    final user = _firebaseAuth?.currentUser;
    return user != null &&
        !_emailVerificationRequired &&
        _session == null &&
        !_initializationFailed;
  }

  bool get shouldAutoRetryBackendSession =>
      canRetryBackendSession &&
      !_configurationFailed &&
      isTransientBackendSessionFailure(_backendSessionError);

  String? _smsVerificationId;
  String? _smsDestination;
  SmsChallengePurpose? _smsChallengePurpose;
  MultiFactorResolver? _multiFactorResolver;
  bool _hasEnrolledSmsMfa = false;

  // Function Name: smsCodeRequired
  // Description: Reports whether a verification identifier is waiting for user-entered SMS digits.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether a verification identifier is waiting for user-entered SMS digits.
  bool get smsCodeRequired => _smsVerificationId != null;
  // Function Name: smsDestination
  // Description: Exposes the phone destination associated with the pending SMS challenge.
  // Parameters:
  // - None.
  // Returns:
  // - String?: The phone destination associated with the pending SMS challenge.
  String? get smsDestination => _smsDestination;
  // Function Name: smsChallengePurpose
  // Description: Exposes whether the pending SMS code completes sign-in or second-factor enrollment.
  // Parameters:
  // - None.
  // Returns:
  // - SmsChallengePurpose?: Whether the pending SMS code completes sign-in or second-factor enrollment.
  SmsChallengePurpose? get smsChallengePurpose => _smsChallengePurpose;

  // Function Name: canEnrollSmsMfa
  // Description: Requires enabled phone authentication and a nonanonymous, email-verified account with a nonphone provider before offering SMS enrollment.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Requires enabled phone authentication and a nonanonymous, email-verified account with a nonphone provider before offering SMS enrollment.
  bool get canEnrollSmsMfa {
    if (!phoneAuthenticationEnabled) {
      return false;
    }
    final user = _firebaseAuth?.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) {
      return false;
    }
    return user.providerData.any(
      // Function Name: any callback
      // Description: Identifies a linked sign-in provider other than phone authentication.
      // Parameters:
      // - provider (UserInfo): Authentication provider linked to the current Firebase user.
      // Returns:
      // - Whether this provider is not the phone provider.
      (provider) => provider.providerId != PhoneAuthProvider.PROVIDER_ID,
    );
  }

  // Function Name: hasEnrolledSmsMfa
  // Description: Exposes the most recently retrieved phone-factor enrollment state.
  // Parameters:
  // - None.
  // Returns:
  // - bool: The most recently retrieved phone-factor enrollment state.
  bool get hasEnrolledSmsMfa => _hasEnrolledSmsMfa;

  // Function Name: AuthenticationControl._
  // Description: Creates the authenticated API client with a live Firebase token provider and unauthorized-session cleanup callback.
  // Parameters:
  // - client (AuthenticatedApiClient?): Optional owned client for isolated tests.
  // - httpClient (http.Client?): Optional transport for the control's own client, so tests exercise its token provider and unauthorized callback.
  // Returns:
  // - AuthenticationControl: the initialized instance.
  AuthenticationControl._({
    AuthenticatedApiClient? client,
    http.Client? httpClient,
  }) {
    apiClient = client ?? AuthenticatedApiClient(
      inner: httpClient,
      tokenProvider: /* Function Name: tokenProvider callback
       * Description: Fetches the current Firebase user's ID token for authenticated API requests.
       * Parameters:
       * - None.
       * Returns:
       * - A future containing the ID token, or null without a current user.
       */() async => await _firebaseAuth?.currentUser?.getIdToken(),
      onUnauthorized: _invalidateUnauthorizedSession,
    );
  }

  // 함수이름: AuthenticationControl.development
  // 함수역할: 설정된 사용자 해시를 정규화해 보안 서비스 초기화 없이 로컬 개발 세션을 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - AuthenticationControl: 초기화된 인스턴스.
  factory AuthenticationControl.development() {
    final control = AuthenticationControl._();
    control._session = _createLocalSession();
    control._isInitializing = false;
    return control;
  }

  // 실제 계정·메일·서버 요청 없이 인증 흐름을 검증한다. 주입 클라이언트도 dispose에서 닫는다.
  // httpClient는 컨트롤이 직접 만든 클라이언트의 전송 계층만 바꾸고, observeIdTokenChanges는
  // 앱 시작 때와 같은 토큰 변경 구독을 연결한다.
  @visibleForTesting
  factory AuthenticationControl.withFirebaseAuth(
    FirebaseAuth firebaseAuth, {
    AuthenticatedApiClient? apiClient,
    http.Client? httpClient,
    bool observeIdTokenChanges = false,
  }) {
    final control = AuthenticationControl._(
      client: apiClient,
      httpClient: httpClient,
    );
    control._firebaseAuth = firebaseAuth;
    control._isInitializing = false;
    if (observeIdTokenChanges) {
      control._observeIdTokenChanges(firebaseAuth);
    }
    return control;
  }

  // Function Name: bootstrap
  // Description: Creates the control and starts secure-service initialization without delaying construction of the application.
  // Parameters:
  // - None.
  // Returns:
  // - AuthenticationControl: Creates the control and starts secure-service initialization without delaying construction of the application.
  static AuthenticationControl bootstrap() {
    final control = AuthenticationControl._();
    unawaited(control._initialize());
    return control;
  }

  // Function Name: setBeforeSignOut
  // Description: Registers the application-owned cleanup boundary that must finish while the current Firebase token can still authorize backend requests.
  // Parameters:
  // - callback (Future<void> Function()?): Optional asynchronous cleanup invoked before provider sign-out.
  // Returns:
  // - No return value.
  void setBeforeSignOut(Future<void> Function()? callback) {
    _beforeSignOut = callback;
  }

  // 함수이름: _initialize
  // 함수역할: API·인증 설정을 검증하고 Firebase 또는 명시적 로컬 모드를 초기화하며 토큰 변경 구독과 복구 가능한 실패 상태를 연결한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _initialize() async {
    _configurationFailed = false;
    _initializationFailed = false;
    try {
      ApiConfig.validate();
      AuthConfig.validate();
    } catch (_) {
      _configurationFailed = true;
      _backendSessionError = null;
      _errorCode = AuthenticationErrorCode.configuration;
      _errorMessage = AuthenticationErrorCode.configuration.english;
      _finishInitialization();
      return;
    }

    try {
      if (AuthConfig.mode == AuthenticationMode.disabled) {
        _session = _createLocalSession();
        return;
      }
      await FirebaseRuntimeService.initialize();
      final firebaseAuth = FirebaseAuth.instance;
      _firebaseAuth = firebaseAuth;
      if (AuthConfig.authEmulatorHost.isNotEmpty) {
        await firebaseAuth
            .useAuthEmulator(
              AuthConfig.authEmulatorHost,
              AuthConfig.authEmulatorPort,
            )
            .timeout(_authenticationOperationTimeout);
      }
      await _authSubscription?.cancel();
      _observeIdTokenChanges(firebaseAuth);
      await _synchronizeUser(firebaseAuth.currentUser);
    } catch (_) {
      _initializationFailed = true;
      _clearSession();
      _backendSessionError = null;
      _errorCode = AuthenticationErrorCode.initialization;
      _errorMessage = AuthenticationErrorCode.initialization.english;
    } finally {
      _finishInitialization();
    }
  }

  // Function Name: _observeIdTokenChanges
  // Description: Subscribes to Firebase token changes so every sign-in, sign-out, and token refresh is reconciled with the backend session.
  // Parameters:
  // - firebaseAuth (FirebaseAuth): Initialized Firebase authentication instance to observe.
  // Returns:
  // - No return value.
  void _observeIdTokenChanges(FirebaseAuth firebaseAuth) {
    _authSubscription = firebaseAuth.idTokenChanges().listen(
      _synchronizeUser,
      onError: /* Function Name: onError callback
       * Description: Converts authentication-state stream failures into the control's refresh error state.
       * Parameters:
       * - error (Object): Original failure object to classify or record.
       * - stackTrace (StackTrace): Call stack recorded alongside the error.
       * Returns:
       * - No return value.
       */(Object error, StackTrace stackTrace) {
        _setErrorCode(AuthenticationErrorCode.stateRefreshFailed);
      },
    );
  }

  // Function Name: retryInitialization
  // Description: Repeats Firebase and App Check bootstrap after a recoverable startup failure without enabling an unauthenticated local fallback.
  // Parameters:
  // - None.
  // Returns:
  // - Completes after the retry succeeds or publishes a new recoverable error.
  Future<void> retryInitialization() async {
    if (_isInitializing || _isBusy || _configurationFailed) {
      return;
    }
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();
    await _initialize();
  }

  // Function Name: retryBackendSession
  // Description: Reuses the current Firebase identity to retry only the authenticated backend session handshake after connectivity is restored.
  // Parameters:
  // - None.
  // Returns:
  // - Completes after the session is synchronized or a bounded error is shown.
  Future<void> retryBackendSession() async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Requires a signed-in Firebase user and retries synchronization with the secure backend session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of secure-session synchronization; absence of a user throws.
     */() async {
      final user = _requireFirebaseAuth().currentUser;
      if (user == null) {
        throw AuthenticationStateError(
          AuthenticationErrorCode.retryRequiresSignIn,
        );
      }
      await _synchronizeUser(user);
    });
  }

  // Function Name: _finishInitialization
  // Description: Releases the startup gate and notifies authentication listeners of the final initialization state.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void _finishInitialization() {
    _isInitializing = false;
    notifyListeners();
  }

  // 함수이름: _createLocalSession
  // 함수역할: 빌드 설정의 기기별 사용자 해시를 정규화해 서버 인증을 거치지 않은 로컬 테스트 세션을 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - AuthSession: 빌드 설정의 기기별 사용자 해시를 정규화해 서버 인증을 거치지 않은 로컬 테스트 세션을 만든다.
  // 비고:
  // - 인증을 사용하지 않는 로컬 연동 테스트에서는 실행 옵션으로 기기별 사용자를 구분한다.
  static AuthSession _createLocalSession() {
    return AuthSession(
      userHash: PatientHash.normalizePatientHash(AuthConfig.localUserHash),
      authenticated: false,
    );
  }

  // Function Name: signIn
  // Description: Signs in with a trimmed email and password, then synchronizes the resulting Firebase identity with the backend.
  // Parameters:
  // - email (String): Email used for sign-in, verification, or password reset.
  // - password (String): Password for the email account.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> signIn({required String email, required String password}) async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Signs in with trimmed email credentials and synchronizes the resulting Firebase user.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of sign-in and backend-session synchronization.
     */() async {
      final firebaseAuth = _requireFirebaseAuth();
      final credential = await firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _synchronizeUser(credential.user ?? firebaseAuth.currentUser);
    });
  }

  // Function Name: signInAnonymously
  // Description: Creates a Firebase guest identity and establishes its MedBuddy backend session.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> signInAnonymously() async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Creates an anonymous Firebase sign-in and synchronizes its backend session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of anonymous sign-in and session synchronization.
     */() async {
      final firebaseAuth = _requireFirebaseAuth();
      final credential = await firebaseAuth.signInAnonymously();
      await _synchronizeUser(credential.user ?? firebaseAuth.currentUser);
    });
  }

  // Function Name: signInWithGoogle
  // Description: Obtains a Google identity token, signs in or upgrades an anonymous Firebase user, and synchronizes the backend without timing out interactive provider selection.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> signInWithGoogle() async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Initializes Google sign-in once, requires its ID token, and signs in or upgrades the anonymous account.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of Google authentication and session synchronization.
     */() async {
      if (!_googleSignInInitialized) {
        await _googleSignIn.initialize();
        _googleSignInInitialized = true;
      }
      final googleUser = await _googleSignIn.authenticate();
      final googleAuthentication = googleUser.authentication;
      final idToken = googleAuthentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw AuthenticationStateError(
          AuthenticationErrorCode.googleIdentityTokenMissing,
        );
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final firebaseCredential = await _signInOrUpgradeAnonymousUser(
        credential,
      );
      await _synchronizeUser(
        firebaseCredential.user ?? _requireFirebaseAuth().currentUser,
      );
    }, timeout: null);
  }

  // Function Name: startPhoneSignIn
  // Description: Validates international phone syntax and requests an SMS challenge, retaining a manual-code path after automatic retrieval times out.
  // Parameters:
  // - phoneNumber (String): Phone number including the international country code.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> startPhoneSignIn(String phoneNumber) async {
    if (!phoneAuthenticationEnabled) {
      _setErrorCode(AuthenticationErrorCode.phoneAuthenticationUnavailable);
      return;
    }
    final normalizedPhoneNumber = phoneNumber.trim();
    if (!normalizedPhoneNumber.startsWith('+')) {
      _setErrorCode(AuthenticationErrorCode.internationalPhoneNumberRequired);
      return;
    }
    _clearSmsChallenge(notify: false);
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Starts SMS verification for the normalized phone number and registers sign-in challenge handlers.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of the phone-verification request, not SMS verification itself.
     */() async {
      await _requireFirebaseAuth().verifyPhoneNumber(
        phoneNumber: normalizedPhoneNumber,
        verificationCompleted: _completePhoneSignInAutomatically,
        verificationFailed: _handlePhoneVerificationFailure,
        codeSent: /* Function Name: codeSent callback
         * Description: Stores the issued verification ID and destination as a phone sign-in challenge.
         * Parameters:
         * - verificationId (String): SMS verification identifier issued by Firebase.
         * - resendToken (int?): Firebase resend token, unused by this callback.
         * Returns:
         * - No return value.
         */(verificationId, resendToken) {
          _setSmsChallenge(
            verificationId: verificationId,
            destination: normalizedPhoneNumber,
            purpose: SmsChallengePurpose.phoneSignIn,
          );
        },
        codeAutoRetrievalTimeout: /* Function Name: codeAutoRetrievalTimeout callback
         * Description: Preserves an existing SMS challenge or creates one when automatic retrieval expires before code delivery.
         * Parameters:
         * - verificationId (String): SMS verification identifier issued by Firebase.
         * Returns:
         * - No return value.
         */(verificationId) {
          if (_smsVerificationId == null) {
            _setSmsChallenge(
              verificationId: verificationId,
              destination: normalizedPhoneNumber,
              purpose: SmsChallengePurpose.phoneSignIn,
            );
          }
        },
      );
    });
  }

  // Function Name: startSmsMfaEnrollment
  // Description: Requests an enrollment SMS only for an eligible verified account and an international phone number.
  // Parameters:
  // - phoneNumber (String): Phone number including the international country code.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> startSmsMfaEnrollment(String phoneNumber) async {
    if (!phoneAuthenticationEnabled) {
      _setErrorCode(AuthenticationErrorCode.smsVerificationUnavailable);
      return;
    }
    final user = _requireFirebaseAuth().currentUser;
    final normalizedPhoneNumber = phoneNumber.trim();
    if (user == null || !canEnrollSmsMfa) {
      _setErrorCode(AuthenticationErrorCode.mfaVerifiedEmailRequired);
      return;
    }
    if (!normalizedPhoneNumber.startsWith('+')) {
      _setErrorCode(AuthenticationErrorCode.internationalPhoneNumberRequired);
      return;
    }
    _clearSmsChallenge(notify: false);
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Starts phone verification within the user's multi-factor enrollment session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of the enrollment SMS request.
     */() async {
      final session = await user.multiFactor.getSession();
      await _requireFirebaseAuth().verifyPhoneNumber(
        multiFactorSession: session,
        phoneNumber: normalizedPhoneNumber,
        verificationCompleted: /* Function Name: verificationCompleted callback
         * Description: Leaves enrollment completion to explicit SMS-code confirmation instead of accepting automatic verification.
         * Parameters:
         * - _ (PhoneAuthCredential): Unused event value supplied by the enclosing callback contract.
         * Returns:
         * - No return value.
         */(_) {},
        verificationFailed: _handlePhoneVerificationFailure,
        codeSent: /* Function Name: codeSent callback
         * Description: Records the verification ID and phone destination for multi-factor enrollment.
         * Parameters:
         * - verificationId (String): SMS verification identifier issued by Firebase.
         * - resendToken (int?): Firebase resend token, unused by this callback.
         * Returns:
         * - No return value.
         */(verificationId, resendToken) {
          _setSmsChallenge(
            verificationId: verificationId,
            destination: normalizedPhoneNumber,
            purpose: SmsChallengePurpose.mfaEnrollment,
          );
        },
        codeAutoRetrievalTimeout: /* Function Name: codeAutoRetrievalTimeout callback
         * Description: Keeps the enrollment challenge unchanged when automatic SMS retrieval expires.
         * Parameters:
         * - _ (String): Unused event value supplied by the enclosing callback contract.
         * Returns:
         * - No return value.
         */(_) {},
      );
    });
  }

  // Function Name: submitSmsCode
  // Description: Validates the pending six-digit challenge and routes its credential to phone sign-in, MFA resolution, or factor enrollment before refreshing the session.
  // Parameters:
  // - smsCode (String): SMS verification code entered by the user.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> submitSmsCode(String smsCode) async {
    if (!phoneAuthenticationEnabled) {
      _clearSmsChallenge(notify: false);
      _setErrorCode(AuthenticationErrorCode.smsVerificationUnavailable);
      return;
    }
    final verificationId = _smsVerificationId;
    final purpose = _smsChallengePurpose;
    if (verificationId == null || purpose == null) {
      _setErrorCode(AuthenticationErrorCode.smsCodeNotRequested);
      return;
    }
    final normalizedCode = smsCode.trim();
    if (normalizedCode.length < 6) {
      _setErrorCode(AuthenticationErrorCode.smsCodeIncomplete);
      return;
    }
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Applies the entered SMS credential to sign-in, MFA resolution, or MFA enrollment, then clears the challenge and refreshes the session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of credential verification and session synchronization.
     */() async {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: normalizedCode,
      );
      switch (purpose) {
        case SmsChallengePurpose.phoneSignIn:
          await _signInOrUpgradeAnonymousUser(credential);
        case SmsChallengePurpose.mfaSignIn:
          final resolver = _multiFactorResolver;
          if (resolver == null) {
            throw AuthenticationStateError(
              AuthenticationErrorCode.mfaSignInExpired,
            );
          }
          await resolver.resolveSignIn(
            PhoneMultiFactorGenerator.getAssertion(credential),
          );
        case SmsChallengePurpose.mfaEnrollment:
          final user = _requireFirebaseAuth().currentUser;
          if (user == null) {
            throw AuthenticationStateError(
              AuthenticationErrorCode.mfaEnrollmentExpired,
            );
          }
          await user.multiFactor.enroll(
            PhoneMultiFactorGenerator.getAssertion(credential),
            displayName: 'MedBuddy SMS',
          );
      }
      _clearSmsChallenge(notify: false);
      await _synchronizeUser(_requireFirebaseAuth().currentUser);
    });
  }

  // Function Name: cancelSmsChallenge
  // Description: Clears the pending verification identifier, destination, purpose, and MFA resolver and notifies the sign-in UI.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void cancelSmsChallenge() {
    _clearSmsChallenge();
  }

  // Function Name: createAccount
  // Description: Links email credentials to an anonymous identity or creates an email account, sends verification, and refreshes the authentication gate.
  // Parameters:
  // - email (String): Email used for sign-in, verification, or password reset.
  // - password (String): Password for the email account.
  // - language (String): Selected app language for the verification email; defaults to Korean.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> createAccount({
    required String email,
    required String password,
    String language = 'ko',
  }) async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Links email credentials to an anonymous account or creates a new account, then sends email verification and synchronizes it.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of account creation or linking and verification-email dispatch.
     */() async {
      final firebaseAuth = _requireFirebaseAuth();
      final currentUser = firebaseAuth.currentUser;
      late final User? account;
      if (currentUser?.isAnonymous == true) {
        final credential = EmailAuthProvider.credential(
          email: email.trim(),
          password: password,
        );
        account = (await currentUser!.linkWithCredential(credential)).user;
      } else {
        account = (await firebaseAuth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        )).user;
      }
      // Apply the requested language inside the serialized operation, before dispatch.
      await firebaseAuth.setLanguageCode(
        AppLanguageControl.normalizeLanguage(language),
      );
      await account?.sendEmailVerification();
      await _synchronizeUser(account);
    });
  }

  // Function Name: sendPasswordReset
  // Description: Rejects blank email input and sends a password-reset email through the guarded authentication flow.
  // Parameters:
  // - email (String): Email used for sign-in, verification, or password reset.
  // - language (String): Selected app language for the password-reset email.
  // Returns:
  // - Future<bool>: Rejects blank email input and sends a password-reset email through the guarded authentication flow.
  Future<bool> sendPasswordReset(String email, {String language = 'ko'}) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      _setErrorCode(AuthenticationErrorCode.emailRequired);
      return false;
    }
    var sent = false;
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Sends the password-reset email and records successful dispatch in the enclosing operation.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of password-reset email dispatch.
     */ () async {
      final firebaseAuth = _requireFirebaseAuth();
      await firebaseAuth.setLanguageCode(
        AppLanguageControl.normalizeLanguage(language),
      );
      await firebaseAuth.sendPasswordResetEmail(email: normalizedEmail);
      sent = true;
    });
    return sent;
  }

  // Function Name: resendEmailVerification
  // Description: Sends another verification email for the current user and surfaces missing-session or provider failures.
  // Parameters:
  // - language (String): Current app language, including changes made after signup.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> resendEmailVerification({String language = 'ko'}) async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Requires a current Firebase user before resending their email-verification message.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of verification-email dispatch.
     */ () async {
      final firebaseAuth = _requireFirebaseAuth();
      final user = firebaseAuth.currentUser;
      if (user == null) {
        throw AuthenticationStateError(AuthenticationErrorCode.noSignedInUser);
      }
      await firebaseAuth.setLanguageCode(
        AppLanguageControl.normalizeLanguage(language),
      );
      await user.sendEmailVerification();
    });
  }

  // Function Name: refreshEmailVerification
  // Description: Reloads the Firebase user, refreshes the token after successful verification, and retries backend session synchronization.
  // Parameters:
  // - showPendingMessage (bool): Whether an unverified result should display manual-check guidance.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> refreshEmailVerification({bool showPendingMessage = true}) async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Reloads email-verification status, refreshes the token after verification, and resynchronizes the backend session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of user reload and session synchronization.
     */() async {
      final user = _requireFirebaseAuth().currentUser;
      if (user == null) {
        throw AuthenticationStateError(AuthenticationErrorCode.noSignedInUser);
      }
      await user.reload();
      final refreshedUser = _requireFirebaseAuth().currentUser;
      if (refreshedUser?.emailVerified == true) {
        await refreshedUser?.getIdToken(true);
      }
      await _synchronizeUser(refreshedUser);
      // 미인증은 화면을 유지하되, 재확인 결과와 다음 행동을 분명히 안내한다.
      if (_emailVerificationRequired && showPendingMessage) {
        _setErrorCode(AuthenticationErrorCode.emailVerificationPending);
      }
    }, clearError: showPendingMessage);
  }

  // Function Name: signOut
  // Description: Awaits application cleanup while the token is usable, signs out providers, and clears SMS and backend session state.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> signOut() {
    return _signOut(/* Function Name: _signOut callback
     * Description: Signs out an initialized Google provider and then the Firebase identity.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of provider sign-out.
     */() async {
      if (_googleSignInInitialized) {
        await _googleSignIn.signOut();
      }
      await _requireFirebaseAuth().signOut();
    });
  }

  // Function Name: establishSessionForTest
  // Description: Publishes a signed-in session for the given account without a provider or backend, so a test can sign a second account in after a sign-out.
  // Parameters:
  // - userHash (String): Account key of the session to publish.
  // Returns:
  // - No return value.
  @visibleForTesting
  void establishSessionForTest(String userHash) {
    _session = AuthSession(
      userHash: PatientHash.normalizePatientHash(userHash),
      authenticated: false,
    );
    notifyListeners();
  }

  // Function Name: signOutForTest
  // Description: Runs the same strict sign-out sequence as signOut with an injected provider operation instead of a live Firebase session.
  // Parameters:
  // - providerSignOut (Future<void> Function()): Asynchronous provider sign-out boundary, injectable for testing.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  @visibleForTesting
  Future<void> signOutForTest(Future<void> Function() providerSignOut) {
    return _signOut(providerSignOut);
  }

  // Function Name: _signOut
  // Description: Runs pre-sign-out cleanup while the token is still usable, then the provider sign-out, and finally clears SMS and backend session state. A cleanup failure stops the sequence before the provider session is released.
  // Parameters:
  // - providerSignOut (Future<void> Function()): Provider sign-out operation; the live providers in production.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _signOut(Future<void> Function() providerSignOut) async {
    await _runStrictAuthOperation(/* Function Name: _runStrictAuthOperation callback
     * Description: Runs pre-sign-out cleanup before signing out providers, clearing SMS state, and publishing an empty session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of cleanup and provider sign-out.
     */() async {
      await _beforeSignOut?.call();
      await providerSignOut();
      _clearSmsChallenge(notify: false);
      await _synchronizeUser(null);
    });
  }

  // Function Name: prepareAccountDeletion
  // Description: Refreshes or reauthenticates the current Firebase identity before the backend performs irreversible deletion. Anonymous guests remain deletable because Firebase does not provide a reusable credential for anonymous step-up authentication.
  // Parameters:
  // - None.
  // Returns:
  // - Completes with a fresh token, or throws with a user-actionable message.
  Future<void> prepareAccountDeletion() async {
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      return;
    }
    final user = _requireFirebaseAuth().currentUser;
    if (user == null) {
      throw AuthenticationStateError(
        AuthenticationErrorCode.deletionRequiresSignIn,
      );
    }
    if (user.isAnonymous) {
      await user.getIdToken(true);
      return;
    }

    final lastSignIn = user.metadata.lastSignInTime?.toUtc();
    final recentlySignedIn =
        lastSignIn != null &&
        DateTime.now().toUtc().difference(lastSignIn) <=
            const Duration(minutes: 4);
    if (recentlySignedIn) {
      await user.getIdToken(true);
      return;
    }

    final usesGoogle = user.providerData.any(
      // Function Name: any callback
      // Description: Detects Google as a linked authentication provider for reauthentication.
      // Parameters:
      // - provider (UserInfo): Authentication provider linked to the current Firebase user.
      // Returns:
      // - Whether this entry is the Google provider.
      (provider) => provider.providerId == GoogleAuthProvider.PROVIDER_ID,
    );
    if (!usesGoogle) {
      throw AuthenticationStateError(
        AuthenticationErrorCode.deletionRequiresRecentSignIn,
      );
    }

    await _runStrictAuthOperation(/* Function Name: _runStrictAuthOperation callback
     * Description: Obtains a fresh Google credential, reauthenticates the current user, and forces an ID-token refresh.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of Google reauthentication and token refresh.
     */() async {
      if (!_googleSignInInitialized) {
        await _googleSignIn.initialize();
        _googleSignInInitialized = true;
      }
      final googleUser = await _googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw AuthenticationStateError(
          AuthenticationErrorCode.googleIdentityTokenMissing,
        );
      }
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      await user.getIdToken(true);
    });
  }

  // Function Name: finishAccountDeletion
  // Description: Clears the local Firebase session after the backend has deleted MedBuddy data and the Firebase identity through its trusted Admin boundary. Avoids a second client-side identity deletion and its recent-login race.
  // Parameters:
  // - None.
  // Returns:
  // - Completes after the local authentication gate returns to sign-in.
  Future<void> finishAccountDeletion() async {
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      _session = _createLocalSession();
      notifyListeners();
      return;
    }
    final firebaseAuth = _requireFirebaseAuth();
    _deletedFirebaseSubject = firebaseAuth.currentUser?.uid;
    await _finishDeletedSession(/* Function Name: _finishDeletedSession callback
     * Description: Signs out Firebase and an initialized Google provider after account deletion.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of provider sign-out.
     */() async {
      await firebaseAuth.signOut();
      if (_googleSignInInitialized) {
        await _googleSignIn.signOut();
      }
    });
  }

  // Function Name: finishAccountDeletionForTest
  // Description: Exercises deleted-session clearing with an injected provider sign-out operation.
  // Parameters:
  // - providerSignOut (Future<void> Function()): Asynchronous provider sign-out boundary, injectable for testing.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  @visibleForTesting
  Future<void> finishAccountDeletionForTest(
    Future<void> Function() providerSignOut,
  ) => _finishDeletedSession(providerSignOut);

  // Function Name: _finishDeletedSession
  // Description: Invalidates in-flight session responses and clears identity, MFA, and SMS state before running provider sign-out.
  // Parameters:
  // - providerSignOut (Future<void> Function()): Asynchronous provider sign-out boundary, injectable for testing.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _finishDeletedSession(
    Future<void> Function() providerSignOut,
  ) async {
    _sessionGeneration += 1;
    _signedInEmail = null;
    _emailVerificationRequired = false;
    _hasEnrolledSmsMfa = false;
    _clearSmsChallenge(notify: false);
    _clearSession();
    notifyListeners();
    await _runStrictAuthOperation(providerSignOut);
  }

  // Function Name: _runStrictAuthOperation
  // Description: Serializes bounded authentication work and publishes translated failures while rethrowing them to cleanup callers. A canceled Google prompt is rethrown without being published as an error.
  // Parameters:
  // - operation (Future<void> Function()): Authentication operation run inside serialization and error handling.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _runStrictAuthOperation(
    Future<void> Function() operation,
  ) async {
    if (_isBusy) {
      throw AuthenticationStateError(
        AuthenticationErrorCode.operationInProgress,
      );
    }
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation().timeout(_authenticationOperationTimeout);
    } on FirebaseAuthException catch (error) {
      final code = _codeForFirebaseError(error.code);
      _setErrorCode(code);
      throw AuthenticationStateError(code);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw AuthenticationStateError(
          AuthenticationErrorCode.googleSignInCanceled,
        );
      }
      _setErrorCode(AuthenticationErrorCode.googleSignInIncomplete);
      throw AuthenticationStateError(
        AuthenticationErrorCode.googleSignInIncomplete,
      );
    } on TimeoutException {
      _setErrorCode(AuthenticationErrorCode.timeout);
      throw AuthenticationStateError(AuthenticationErrorCode.timeout);
    } on StateError catch (error) {
      _setStateError(error);
      rethrow;
    } catch (_) {
      _setErrorCode(AuthenticationErrorCode.requestFailed);
      throw AuthenticationStateError(AuthenticationErrorCode.requestFailed);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  // Function Name: _runAuthOperation
  // Description: Serializes authentication work, handles MFA challenges and provider errors, and always releases the busy state; an optional null timeout permits interactive sign-in. Backing out of the Google account picker leaves no error.
  // Parameters:
  // - operation (Future<void> Function()): Authentication operation run inside serialization and error handling.
  // - timeout (Duration?): Authentication timeout; null waits without a time limit.
  // - clearError (bool): Whether to clear previous guidance before the request starts.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _runAuthOperation(
    Future<void> Function() operation, {
    Duration? timeout = _authenticationOperationTimeout,
    bool clearError = true,
  }) async {
    if (_isBusy) {
      return;
    }
    _isBusy = true;
    if (clearError) _errorMessage = null;
    notifyListeners();
    try {
      final pendingOperation = operation();
      if (timeout == null) {
        await pendingOperation;
      } else {
        await pendingOperation.timeout(timeout);
      }
    } on FirebaseAuthMultiFactorException catch (error) {
      await _beginMfaSignIn(error.resolver);
    } on FirebaseAuthException catch (error) {
      _setErrorCode(_codeForFirebaseError(error.code));
    } on GoogleSignInException catch (error) {
      // The plugin always supplies its own description, so the failure is
      // identified by code; closing the account picker is not a failure.
      if (error.code != GoogleSignInExceptionCode.canceled) {
        _setErrorCode(AuthenticationErrorCode.googleSignInIncomplete);
      }
    } on StateError catch (error) {
      _setStateError(error);
    } on TimeoutException {
      _setErrorCode(AuthenticationErrorCode.timeout);
    } catch (_) {
      _setErrorCode(AuthenticationErrorCode.requestFailed);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  // Function Name: runAuthOperationForTest
  // Description: Runs an injected operation through the same serialization and error translation as the sign-in commands, so provider failures can be exercised without a live provider.
  // Parameters:
  // - operation (Future<void> Function()): Operation standing in for a provider call.
  // - strict (bool): Whether to use the rethrowing wrapper used by sign-out and account deletion.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  @visibleForTesting
  Future<void> runAuthOperationForTest(
    Future<void> Function() operation, {
    bool strict = false,
  }) {
    return strict
        ? _runStrictAuthOperation(operation)
        : _runAuthOperation(operation);
  }

  // 함수이름: _synchronizeUser
  // 함수역할: Firebase 신원을 이메일 검증·MFA 상태와 조정하고 삭제된 신원과 오래된 응답을 제외한 뒤 인증된 백엔드 교환 결과만 세션으로 채택한다. 더 새로운 동기화가 시작되면 그 결과가 정해질 때까지 기다린 뒤 반환한다.
  // 매개변수:
  // - user (User?): 현재 또는 새로 복원된 Firebase 사용자
  // - scheduledRetry (bool): 유지된 세션을 확인하려고 예약한 재시도인지 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _synchronizeUser(User? user, {bool scheduledRetry = false}) {
    final generation = ++_sessionGeneration;
    final synchronization = _runSynchronization(
      user,
      generation,
      scheduledRetry: scheduledRetry,
    );
    _latestSynchronization = synchronization;
    _latestSynchronizationGeneration = generation;
    return synchronization;
  }

  // 함수이름: _runSynchronization
  // 함수역할: 한 번의 세션 동기화를 수행한다. 로그아웃·이메일 미인증은 세션을 즉시 끝내고, 서버 교환이 실패하면 실패 원인을 분류해 세션을 끝낼지 유지할지 정한다.
  // 매개변수:
  // - user (User?): 현재 또는 새로 복원된 Firebase 사용자
  // - generation (int): 이 동기화에 부여된 세대 번호. 더 큰 번호가 생기면 결과를 적용하지 않는다.
  // - scheduledRetry (bool): 유지된 세션을 확인하려고 예약한 재시도인지 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _runSynchronization(
    User? user,
    int generation, {
    required bool scheduledRetry,
  }) async {
    final deletedSubject = _deletedFirebaseSubject;
    if (user != null && user.uid == deletedSubject) {
      _clearSession();
      _signedInEmail = null;
      _emailVerificationRequired = false;
      notifyListeners();
      return;
    }
    if (user != null && deletedSubject != null && user.uid != deletedSubject) {
      _deletedFirebaseSubject = null;
    }
    _signedInEmail = user?.email;
    _emailVerificationRequired = _requiresEmailVerification(user);
    await _refreshMfaEnrollment(user);
    if (generation != _sessionGeneration) {
      await _awaitNewerSynchronization(generation);
      return;
    }
    if (user == null || _emailVerificationRequired) {
      _clearSession();
      notifyListeners();
      return;
    }

    AuthSession? session;
    Object? failure;
    try {
      session = await _requestBackendSession(user);
    } catch (error) {
      failure = error;
    }
    if (generation != _sessionGeneration) {
      await _awaitNewerSynchronization(generation);
      return;
    }
    if (session != null) {
      _session = session;
      _sessionSubject = user.uid;
      _cancelSessionResync();
      _errorMessage = null;
      _backendSessionError = null;
    } else {
      await _resolveSessionFailure(
        failure!,
        user,
        generation,
        scheduledRetry: scheduledRetry,
      );
    }
    if (generation == _sessionGeneration) {
      notifyListeners();
    }
  }

  // 함수이름: _awaitNewerSynchronization
  // 함수역할: 대체된 동기화가 최신 동기화의 결과가 정해지기 전에 호출자에게 돌아가지 않게 한다. 시작·로그인 흐름이 세션 없이 먼저 끝나 로그인 화면이 잠깐 보이는 것을 막는다.
  // 매개변수:
  // - generation (int): 대체된 동기화의 세대 번호
  // 반환값:
  // - Future<void>: 더 새로운 동기화가 끝나면 완료된다. 계정 삭제·dispose처럼 새 동기화 없이 무효화된 경우에는 바로 완료된다.
  Future<void> _awaitNewerSynchronization(int generation) async {
    final newer = _latestSynchronization;
    if (newer == null || _latestSynchronizationGeneration <= generation) {
      return;
    }
    try {
      await newer;
    } catch (_) {
      // 최신 동기화의 실패는 그 호출자가 직접 처리한다.
    }
  }

  // 함수이름: _requestBackendSession
  // 함수역할: 현재 ID 토큰을 읽고 백엔드 세션을 요청한다. 같은 사용자·같은 토큰의 요청이 이미 진행 중이면 새 요청을 보내지 않고 그 결과를 함께 사용한다.
  // 매개변수:
  // - user (User): 세션을 요청할 Firebase 사용자
  // 반환값:
  // - Future<AuthSession>: 서버가 인증한 세션. 토큰을 읽지 못하면 _IdTokenFailure, 서버 교환이 실패하면 그 원인을 던진다.
  Future<AuthSession> _requestBackendSession(User user) async {
    final token = await _readIdToken(user);
    final pending = _pendingHandshake;
    if (pending != null &&
        pending.subject == user.uid &&
        pending.token == token) {
      return pending.result;
    }
    final handshake = _PendingHandshake(
      user.uid,
      token,
      _fetchBackendSession(),
    );
    _pendingHandshake = handshake;
    try {
      return await handshake.result;
    } finally {
      if (identical(_pendingHandshake, handshake)) {
        _pendingHandshake = null;
      }
    }
  }

  // 함수이름: _readIdToken
  // 함수역할: 서버 교환 전에 Firebase ID 토큰을 직접 읽어, 토큰을 얻지 못한 원인을 일반적인 연결 실패와 구분할 수 있게 한다.
  // 매개변수:
  // - user (User): 토큰을 읽을 Firebase 사용자
  // 반환값:
  // - Future<String>: 비어 있지 않은 ID 토큰. 읽지 못하면 원래 실패를 담은 _IdTokenFailure를 던진다.
  Future<String> _readIdToken(User user) async {
    final String? token;
    try {
      token = await user.getIdToken().timeout(_idTokenTimeout);
    } catch (error) {
      throw _IdTokenFailure(error);
    }
    if (token == null || token.trim().isEmpty) {
      throw _IdTokenFailure(StateError('Firebase returned no ID token.'));
    }
    return token;
  }

  // 함수이름: _fetchBackendSession
  // 함수역할: 인증된 백엔드 세션을 한 번 요청하고 응답을 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<AuthSession>: 서버가 인증한 세션. 200이 아닌 응답·형식 오류·미인증 응답은 예외로 알린다.
  Future<AuthSession> _fetchBackendSession() async {
    final response = await apiClient
        .get(Uri.parse(ApiConfig.authSessionUrl))
        .timeout(_backendSessionTimeout);
    if (response.statusCode != 200) {
      throw BackendSessionHttpException(response.statusCode);
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Authentication session is malformed.');
    }
    final session = AuthSession.fromJson(payload);
    if (!session.authenticated) {
      throw const FormatException('Backend session is not authenticated.');
    }
    return session;
  }

  // 함수이름: _resolveSessionFailure
  // 함수역할: 세션 동기화 실패를 분류해 처리한다. 신원이 거부되면 공급자까지 로그아웃하고, 서버가 거절하면 세션을 끝내며, 판정을 얻지 못한 실패는 같은 사용자의 기존 세션을 유지하고 재확인을 예약한다.
  // 매개변수:
  // - failure (Object): 토큰 읽기 또는 서버 교환에서 발생한 실패
  // - user (User): 동기화 대상 Firebase 사용자
  // - generation (int): 이 동기화의 세대 번호
  // - scheduledRetry (bool): 유지된 세션을 확인하려고 예약한 재시도인지 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _resolveSessionFailure(
    Object failure,
    User user,
    int generation, {
    required bool scheduledRetry,
  }) async {
    final kind = await _classifySessionFailure(failure, user);
    if (generation != _sessionGeneration) {
      await _awaitNewerSynchronization(generation);
      return;
    }
    // 토큰을 읽지 못한 실패는 기존과 같은 "신원 확인 불가" 원인으로 기록한다.
    final Object reported = failure is _IdTokenFailure
        ? const AuthenticationUnavailableException()
        : failure;
    final providerHoldsUser = _firebaseAuth?.currentUser?.uid == user.uid;
    final keepsSession =
        kind == _SessionFailureKind.inconclusive &&
        _session != null &&
        _sessionSubject == user.uid &&
        providerHoldsUser;
    // Fixed diagnostic codes are safe in signed builds; no tokens or bodies.
    debugPrint(
      'MedBuddy session failure: ${backendSessionFailureCode(reported)} '
      '(${keepsSession ? 'session kept' : kind.name})',
    );
    if (keepsSession) {
      if (!scheduledRetry) {
        _sessionResyncAttempts = 0;
      }
      _scheduleSessionResync();
      return;
    }
    if (kind == _SessionFailureKind.rejected) {
      if (providerHoldsUser) {
        try {
          await _invalidateUnauthorizedSession();
        } catch (_) {
          // 공급자 로그아웃이 실패해도 아래에서 MedBuddy 세션은 반드시 끝낸다.
        }
      }
      if (_session != null || _errorMessage == null) {
        // 401 처리기가 이미 공급자를 로그아웃했거나 다른 무효화가 진행 중인 경우에도 세션을 남기지 않는다.
        _clearSession();
        _setErrorCode(AuthenticationErrorCode.sessionExpired);
      }
      return;
    }
    _clearSession();
    _setError(
      resolveBackendSessionError(reported, isEnglish: false),
      cause: reported,
    );
  }

  // 함수이름: _classifySessionFailure
  // 함수역할: 세션 동기화 실패가 계정에 대한 판정인지 판정을 얻지 못한 것인지 구분한다.
  // 매개변수:
  // - failure (Object): 토큰 읽기 또는 서버 교환에서 발생한 실패
  // - user (User): 동기화 대상 Firebase 사용자
  // 반환값:
  // - Future<_SessionFailureKind>: rejected(신원 거부·401), refused(403 등 서버 거절·계약 불일치·잘못된 응답), inconclusive(네트워크·TLS 연결 실패·시간 초과·408/429/5xx·토큰 발급 불가).
  Future<_SessionFailureKind> _classifySessionFailure(
    Object failure,
    User user,
  ) async {
    if (failure is _IdTokenFailure) {
      return switch (_classifyIdentityFailure(failure.cause)) {
        _IdentityFailureKind.rejected => _SessionFailureKind.rejected,
        _IdentityFailureKind.unavailable => _SessionFailureKind.inconclusive,
        _IdentityFailureKind.ambiguous => await _probeIdentity(user),
      };
    }
    if (failure is BackendSessionHttpException && failure.statusCode == 401) {
      return _SessionFailureKind.rejected;
    }
    // package:http는 TLS 연결 실패를 ClientException으로 감싸지 않는다. 요청이 서버에 닿지 못했으므로 판정이 아니다.
    if (failure is TlsException) {
      return _SessionFailureKind.inconclusive;
    }
    return isTransientBackendSessionFailure(failure)
        ? _SessionFailureKind.inconclusive
        : _SessionFailureKind.refused;
  }

  // 함수이름: _probeIdentity
  // 함수역할: 토큰 실패 코드만으로 판단할 수 없을 때 사용자 정보를 다시 읽어 계정 상태를 확인한다. Android 플러그인은 getIdToken의 거부 사유를 unknown으로 전달하지만 reload는 원래 코드를 전달한다.
  // 매개변수:
  // - user (User): 상태를 확인할 Firebase 사용자
  // 반환값:
  // - Future<_SessionFailureKind>: 계정·갱신 토큰이 거부되면 rejected, 그 밖의 결과는 inconclusive.
  Future<_SessionFailureKind> _probeIdentity(User user) async {
    try {
      await user.reload().timeout(_identityProbeTimeout);
    } catch (error) {
      if (_classifyIdentityFailure(error) == _IdentityFailureKind.rejected) {
        return _SessionFailureKind.rejected;
      }
    }
    return _SessionFailureKind.inconclusive;
  }

  // 함수이름: _scheduleSessionResync
  // 함수역할: 판정 없이 유지한 세션을 서버와 다시 확인하도록 다음 재시도를 예약한다. 정해진 횟수를 넘으면 다음 토큰 갱신까지 예약하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _scheduleSessionResync() {
    if (_sessionResyncTimer != null ||
        _sessionResyncAttempts >= _sessionResyncDelays.length) {
      return;
    }
    final delay = _sessionResyncDelays[_sessionResyncAttempts];
    _sessionResyncAttempts += 1;
    _sessionResyncTimer = Timer(delay, /* 함수이름: Timer 콜백
     * 함수역할: 같은 사용자의 세션이 아직 유지되고 있을 때만 서버 세션을 다시 확인한다.
     * 매개변수:
     * - 없음.
     * 반환값:
     * - 없음.
     */() {
      _sessionResyncTimer = null;
      final user = _firebaseAuth?.currentUser;
      if (_session == null || user == null || user.uid != _sessionSubject) {
        return;
      }
      unawaited(
        _synchronizeUser(
          user,
          scheduledRetry: true,
        ).catchError((Object _) {}),
      );
    });
  }

  // 함수이름: _cancelSessionResync
  // 함수역할: 예약된 세션 재확인을 취소하고 재시도 횟수를 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _cancelSessionResync() {
    _sessionResyncTimer?.cancel();
    _sessionResyncTimer = null;
    _sessionResyncAttempts = 0;
  }

  // 함수이름: _clearSession
  // 함수역할: 세션과 그 세션이 속한 Firebase 사용자 기록을 함께 지우고 예약된 재확인을 취소한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _clearSession() {
    _session = null;
    _sessionSubject = null;
    _cancelSessionResync();
  }

  // Function Name: handleUnauthorizedResponse
  // Description: Lets API clients created outside this control report an HTTP 401, so the same cleanup and forced sign-out run as for the control's own client.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: completes after the session is invalidated, or immediately without Firebase or while an invalidation is already running.
  Future<void> handleUnauthorizedResponse() => _invalidateUnauthorizedSession();

  // Function Name: _invalidateUnauthorizedSession
  // Description: Starts forced sign-out only when Firebase is available and no unauthorized-session cleanup is already running.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _invalidateUnauthorizedSession() async {
    final firebaseAuth = _firebaseAuth;
    if (firebaseAuth == null || _isInvalidatingUnauthorizedSession) {
      return;
    }
    await _runUnauthorizedSessionInvalidation(firebaseAuth.signOut);
  }

  // Function Name: _runUnauthorizedSessionInvalidation
  // Description: Completes privacy-sensitive local and push cleanup while the current Firebase identity is still available, then forces provider sign-out. Continues the forced sign-out when server-side token cleanup is rejected by the same expired credential that triggered this path.
  // Parameters:
  // - providerSignOut (Future<void> Function()): Firebase provider invalidation operation.
  // Returns:
  // - Completes after the local session and provider identity are cleared.
  Future<void> _runUnauthorizedSessionInvalidation(
    Future<void> Function() providerSignOut,
  ) async {
    if (_isInvalidatingUnauthorizedSession) {
      return;
    }
    _isInvalidatingUnauthorizedSession = true;
    try {
      try {
        await _beforeSignOut?.call();
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            'Expired-session cleanup was only partially completed: '
            '${error.runtimeType}',
          );
        }
      }
      _clearSession();
      _setErrorCode(AuthenticationErrorCode.sessionExpired);
      await providerSignOut();
    } finally {
      _isInvalidatingUnauthorizedSession = false;
    }
  }

  // Function Name: invalidateUnauthorizedSessionForTest
  // Description: Exercises expired-session cleanup and provider invalidation through an injected sign-out boundary.
  // Parameters:
  // - providerSignOut (Future<void> Function()): Asynchronous provider sign-out boundary, injectable for testing.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  @visibleForTesting
  Future<void> invalidateUnauthorizedSessionForTest(
    Future<void> Function() providerSignOut,
  ) {
    return _runUnauthorizedSessionInvalidation(providerSignOut);
  }

  // Function Name: _requireFirebaseAuth
  // Description: Requires initialized Firebase authentication and raises a user-facing state error when it is unavailable.
  // Parameters:
  // - None.
  // Returns:
  // - FirebaseAuth: Requires initialized Firebase authentication and raises a user-facing state error when it is unavailable.
  FirebaseAuth _requireFirebaseAuth() {
    final firebaseAuth = _firebaseAuth;
    if (firebaseAuth == null) {
      throw AuthenticationStateError(
        AuthenticationErrorCode.firebaseUnavailable,
      );
    }
    return firebaseAuth;
  }

  // Function Name: _signInOrUpgradeAnonymousUser
  // Description: Links credentials to a guest account to retain identity, or signs in with those credentials, with a bounded provider timeout.
  // Parameters:
  // - credential (AuthCredential): Provider credential for sign-in or anonymous-account linking.
  // Returns:
  // - Future<UserCredential>: Links credentials to a guest account to retain identity, or signs in with those credentials, with a bounded provider timeout.
  Future<UserCredential> _signInOrUpgradeAnonymousUser(
    AuthCredential credential,
  ) async {
    final firebaseAuth = _requireFirebaseAuth();
    final currentUser = firebaseAuth.currentUser;
    if (currentUser?.isAnonymous == true) {
      return currentUser!
          .linkWithCredential(credential)
          .timeout(_authenticationOperationTimeout);
    }
    return firebaseAuth
        .signInWithCredential(credential)
        .timeout(_authenticationOperationTimeout);
  }

  // Function Name: _requiresEmailVerification
  // Description: Requires verification only for nonanonymous, unverified users with an email-password provider.
  // Parameters:
  // - user (User?): Current or newly restored Firebase user.
  // Returns:
  // - bool: Requires verification only for nonanonymous, unverified users with an email-password provider.
  bool _requiresEmailVerification(User? user) {
    if (user == null || user.isAnonymous || user.emailVerified) {
      return false;
    }
    return user.providerData.any(
      // Function Name: any callback
      // Description: Detects email/password as a linked provider when deciding verification requirements.
      // Parameters:
      // - provider (UserInfo): Authentication provider linked to the current Firebase user.
      // Returns:
      // - Whether this entry is the email/password provider.
      (provider) => provider.providerId == EmailAuthProvider.PROVIDER_ID,
    );
  }

  // Function Name: _refreshMfaEnrollment
  // Description: Refreshes the presence of an enrolled phone factor, treating absent users, provider errors, and timeouts as not enrolled.
  // Parameters:
  // - user (User?): Current or newly restored Firebase user.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _refreshMfaEnrollment(User? user) async {
    if (user == null) {
      _hasEnrolledSmsMfa = false;
      return;
    }
    try {
      final factors = await user.multiFactor.getEnrolledFactors().timeout(
        _mfaStatusTimeout,
      );
      _hasEnrolledSmsMfa = factors.whereType<PhoneMultiFactorInfo>().isNotEmpty;
    } on FirebaseAuthException catch (_) {
      _hasEnrolledSmsMfa = false;
    } on TimeoutException catch (_) {
      _hasEnrolledSmsMfa = false;
    }
  }

  // Function Name: _beginMfaSignIn
  // Description: Selects the first supported phone factor and starts an SMS sign-in challenge while retaining its resolver.
  // Parameters:
  // - resolver (MultiFactorResolver): Resolver for the pending MFA sign-in session.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _beginMfaSignIn(MultiFactorResolver resolver) async {
    if (!phoneAuthenticationEnabled) {
      _setErrorCode(AuthenticationErrorCode.smsVerificationUnavailable);
      return;
    }
    final phoneHint = resolver.hints
        .whereType<PhoneMultiFactorInfo>()
        .firstOrNull;
    if (phoneHint == null) {
      _setErrorCode(AuthenticationErrorCode.mfaFactorUnsupported);
      return;
    }
    _multiFactorResolver = resolver;
    await _requireFirebaseAuth().verifyPhoneNumber(
      multiFactorSession: resolver.session,
      multiFactorInfo: phoneHint,
      verificationCompleted: /* Function Name: verificationCompleted callback
       * Description: Defers multi-factor sign-in completion to explicit SMS-code entry.
       * Parameters:
       * - _ (PhoneAuthCredential): Unused event value supplied by the enclosing callback contract.
       * Returns:
       * - No return value.
       */(_) {},
      verificationFailed: _handlePhoneVerificationFailure,
      codeSent: /* Function Name: codeSent callback
       * Description: Records the selected MFA phone hint and verification ID as a sign-in challenge.
       * Parameters:
       * - verificationId (String): SMS verification identifier issued by Firebase.
       * - resendToken (int?): Firebase resend token, unused by this callback.
       * Returns:
       * - No return value.
       */(verificationId, resendToken) {
        _setSmsChallenge(
          verificationId: verificationId,
          destination: phoneHint.phoneNumber,
          purpose: SmsChallengePurpose.mfaSignIn,
        );
      },
      codeAutoRetrievalTimeout: /* Function Name: codeAutoRetrievalTimeout callback
       * Description: Leaves the MFA sign-in challenge available after automatic SMS retrieval expires.
       * Parameters:
       * - _ (String): Unused event value supplied by the enclosing callback contract.
       * Returns:
       * - No return value.
       */(_) {},
    );
  }

  // Function Name: _completePhoneSignInAutomatically
  // Description: Consumes an automatically verified phone credential, clears the SMS prompt, and synchronizes the resulting identity.
  // Parameters:
  // - credential (PhoneAuthCredential): Provider credential for sign-in or anonymous-account linking.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _completePhoneSignInAutomatically(
    PhoneAuthCredential credential,
  ) async {
    try {
      final firebaseCredential = await _signInOrUpgradeAnonymousUser(
        credential,
      );
      _clearSmsChallenge(notify: false);
      await _synchronizeUser(
        firebaseCredential.user ?? _requireFirebaseAuth().currentUser,
      );
    } on FirebaseAuthException catch (error) {
      _setErrorCode(_codeForFirebaseError(error.code));
    }
  }

  // Function Name: _handlePhoneVerificationFailure
  // Description: Clears the failed SMS challenge and publishes the mapped Firebase error to authentication listeners.
  // Parameters:
  // - error (FirebaseAuthException): Original failure object to classify or record.
  // Returns:
  // - No return value.
  void _handlePhoneVerificationFailure(FirebaseAuthException error) {
    _clearSmsChallenge(notify: false);
    _setErrorCode(_codeForFirebaseError(error.code));
  }

  // Function Name: _setSmsChallenge
  // Description: Stores the verification identifier, destination, and completion purpose while clearing previous errors and refreshing the SMS UI.
  // Parameters:
  // - verificationId (String): Firebase SMS verification-session identifier.
  // - destination (String): International-format destination for the verification SMS.
  // - purpose (SmsChallengePurpose): Sign-in or MFA step completed by the SMS code.
  // Returns:
  // - No return value.
  void _setSmsChallenge({
    required String verificationId,
    required String destination,
    required SmsChallengePurpose purpose,
  }) {
    _smsVerificationId = verificationId;
    _smsDestination = destination;
    _smsChallengePurpose = purpose;
    _errorMessage = null;
    notifyListeners();
  }

  // Function Name: _clearSmsChallenge
  // Description: Resets all SMS challenge and MFA resolver fields, optionally suppressing listener notification during a larger state transition.
  // Parameters:
  // - notify (bool): Whether to notify listening screens after the change or load.
  // Returns:
  // - No return value.
  void _clearSmsChallenge({bool notify = true}) {
    _smsVerificationId = null;
    _smsDestination = null;
    _smsChallengePurpose = null;
    _multiFactorResolver = null;
    if (notify) {
      notifyListeners();
    }
  }

  // 함수이름: _setError
  // 함수역할: 코드가 없는 사용자용 안내와 선택적 백엔드 오류 원인을 저장하고 구독 화면에 변경을 알린다.
  // 매개변수:
  // - message (String): 사용자에게 표시하거나 오류로 보존할 안내 문구
  // - cause (Object?): 언어별 안내에 사용할 원래 서버 세션 오류
  // 반환값:
  // - 없음.
  void _setError(String message, {Object? cause}) {
    _errorMessage = message;
    _errorCode = null;
    _backendSessionError = cause;
    notifyListeners();
  }

  // 함수이름: _setErrorCode
  // 함수역할: 인증 실패 코드를 저장해 화면이 현재 언어의 안내를 고를 수 있게 하고 구독 화면에 변경을 알린다.
  // 매개변수:
  // - code (AuthenticationErrorCode): 언어와 무관한 실패 식별자
  // 반환값:
  // - 없음.
  void _setErrorCode(AuthenticationErrorCode code) {
    _errorMessage = code.english;
    _errorCode = code;
    _backendSessionError = null;
    notifyListeners();
  }

  // 함수이름: _setStateError
  // 함수역할: 인증 코드가 담긴 StateError는 코드로, 그 밖의 StateError는 원래 문구로 저장한다.
  // 매개변수:
  // - error (StateError): 인증 작업 중 발생한 상태 오류
  // 반환값:
  // - 없음.
  void _setStateError(StateError error) {
    if (error is AuthenticationStateError) {
      _setErrorCode(error.code);
    } else {
      _setError(error.message);
    }
  }

  // Function Name: _codeForFirebaseError
  // Description: Maps Firebase error codes to actionable sign-in, phone-verification, or MFA failure codes with a general fallback.
  // Parameters:
  // - code (String): Firebase authentication error code.
  // Returns:
  // - AuthenticationErrorCode: Failure code whose guidance is shown in the current language.
  AuthenticationErrorCode _codeForFirebaseError(String code) => switch (code) {
    'invalid-email' => AuthenticationErrorCode.invalidEmail,
    'invalid-credential' ||
    'user-not-found' ||
    'wrong-password' => AuthenticationErrorCode.wrongCredentials,
    'email-already-in-use' => AuthenticationErrorCode.emailAlreadyInUse,
    'credential-already-in-use' =>
      AuthenticationErrorCode.credentialAlreadyInUse,
    'weak-password' => AuthenticationErrorCode.weakPassword,
    'too-many-requests' => AuthenticationErrorCode.tooManyRequests,
    'network-request-failed' => AuthenticationErrorCode.network,
    'invalid-phone-number' => AuthenticationErrorCode.invalidPhoneNumber,
    'invalid-verification-code' => AuthenticationErrorCode.smsCodeIncorrect,
    'quota-exceeded' => AuthenticationErrorCode.smsQuotaExceeded,
    'requires-recent-login' => AuthenticationErrorCode.mfaRecentSignInRequired,
    'operation-not-allowed' => AuthenticationErrorCode.signInMethodDisabled,
    _ => AuthenticationErrorCode.requestFailed,
  };

  // Function Name: dispose
  // Description: Invalidates outstanding session synchronization, cancels the Firebase token subscription, and closes the API client before disposing the notifier.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  @override
  void dispose() {
    _sessionGeneration += 1;
    _cancelSessionResync();
    _authSubscription?.cancel();
    apiClient.close();
    super.dispose();
  }
}
