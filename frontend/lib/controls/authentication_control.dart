// File Name: authentication_control.dart
// Role: Coordinates Firebase identity, SMS challenges, and authenticated backend sessions.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../entities/auth_session_entity.dart';
import '../entities/authentication_gate_state_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/auth_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/firebase_runtime_service.dart';
import '../services/user_facing_error_message.dart';

// Class Name: SmsChallengePurpose
// Role: Distinguishes phone sign-in, MFA sign-in, and MFA enrollment challenges.
// Responsibilities:
// - Select the credential completion path for an entered SMS code.
enum SmsChallengePurpose { phoneSignIn, mfaSignIn, mfaEnrollment }

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

  FirebaseAuth? _firebaseAuth;
  StreamSubscription<User?>? _authSubscription;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInInitialized = false;
  late final AuthenticatedApiClient apiClient;
  int _sessionGeneration = 0;
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
  Object? _backendSessionError;

  // 함수이름: errorMessageForLanguage
  // 함수역할: 서버 세션 연결 오류를 로그인 화면의 현재 언어에 맞는 안내로 변환한다. 버전 계약 불일치는 앱 업데이트가 필요하다는 구체적인 행동을 안내한다.
  // 매개변수:
  // - isEnglish (bool): 영어 표시 문구를 선택할지 여부
  // 반환값:
  // - String?: 서버 세션 연결 오류를 로그인 화면의 현재 언어에 맞는 안내로 변환한다. 버전 계약 불일치는 앱 업데이트가 필요하다는 구체적인 행동을 안내한다.
  String? errorMessageForLanguage({required bool isEnglish}) {
    if (_errorMessage == null) {
      return null;
    }
    final backendSessionError = _backendSessionError;
    if (backendSessionError == null) {
      return _errorMessage;
    }
    return resolveBackendSessionError(
      backendSessionError,
      isEnglish: isEnglish,
    );
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
  // - None.
  // Returns:
  // - AuthenticationControl: the initialized instance.
  AuthenticationControl._() {
    apiClient = AuthenticatedApiClient(
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
      _errorMessage = 'MedBuddy authentication is not configured correctly.';
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
          _setError('Authentication state could not be refreshed.');
        },
      );
      await _synchronizeUser(firebaseAuth.currentUser);
    } catch (_) {
      _initializationFailed = true;
      _session = null;
      _backendSessionError = null;
      _errorMessage =
          'MedBuddy could not initialize its secure services. Check the network and retry.';
    } finally {
      _finishInitialization();
    }
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
        throw StateError('Sign in before retrying the secure session.');
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
        throw StateError('Google did not return an identity token.');
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
      _setError('Phone authentication is unavailable in this beta build.');
      return;
    }
    final normalizedPhoneNumber = phoneNumber.trim();
    if (!normalizedPhoneNumber.startsWith('+')) {
      _setError('Use an international phone number such as +821012345678.');
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
      _setError('SMS verification is unavailable in this beta build.');
      return;
    }
    final user = _requireFirebaseAuth().currentUser;
    final normalizedPhoneNumber = phoneNumber.trim();
    if (user == null || !canEnrollSmsMfa) {
      _setError('Sign in with a verified email account before enabling MFA.');
      return;
    }
    if (!normalizedPhoneNumber.startsWith('+')) {
      _setError('Use an international phone number such as +821012345678.');
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
      _setError('SMS verification is unavailable in this beta build.');
      return;
    }
    final verificationId = _smsVerificationId;
    final purpose = _smsChallengePurpose;
    if (verificationId == null || purpose == null) {
      _setError('Request a new SMS code first.');
      return;
    }
    final normalizedCode = smsCode.trim();
    if (normalizedCode.length < 6) {
      _setError('Enter the six-digit SMS code.');
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
            throw StateError('The MFA sign-in session has expired.');
          }
          await resolver.resolveSignIn(
            PhoneMultiFactorGenerator.getAssertion(credential),
          );
        case SmsChallengePurpose.mfaEnrollment:
          final user = _requireFirebaseAuth().currentUser;
          if (user == null) {
            throw StateError('The MFA enrollment session has expired.');
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
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> createAccount({
    required String email,
    required String password,
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
      await account?.sendEmailVerification();
      await _synchronizeUser(account);
    });
  }

  // Function Name: sendPasswordReset
  // Description: Rejects blank email input and sends a password-reset email through the guarded authentication flow.
  // Parameters:
  // - email (String): Email used for sign-in, verification, or password reset.
  // Returns:
  // - Future<bool>: Rejects blank email input and sends a password-reset email through the guarded authentication flow.
  Future<bool> sendPasswordReset(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      _setError('Enter your email address first.');
      return false;
    }
    var sent = false;
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Sends the password-reset email and records successful dispatch in the enclosing operation.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of password-reset email dispatch.
     */() async {
      await _requireFirebaseAuth().sendPasswordResetEmail(
        email: normalizedEmail,
      );
      sent = true;
    });
    return sent;
  }

  // Function Name: resendEmailVerification
  // Description: Sends another verification email for the current user and surfaces missing-session or provider failures.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> resendEmailVerification() async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Requires a current Firebase user before resending their email-verification message.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of verification-email dispatch.
     */() async {
      final user = _requireFirebaseAuth().currentUser;
      if (user == null) {
        throw StateError('No signed-in user is available.');
      }
      await user.sendEmailVerification();
    });
  }

  // Function Name: refreshEmailVerification
  // Description: Reloads the Firebase user, refreshes the token after successful verification, and retries backend session synchronization.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> refreshEmailVerification() async {
    await _runAuthOperation(/* Function Name: _runAuthOperation callback
     * Description: Reloads email-verification status, refreshes the token after verification, and resynchronizes the backend session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of user reload and session synchronization.
     */() async {
      final user = _requireFirebaseAuth().currentUser;
      if (user == null) {
        throw StateError('No signed-in user is available.');
      }
      await user.reload();
      final refreshedUser = _requireFirebaseAuth().currentUser;
      if (refreshedUser?.emailVerified == true) {
        await refreshedUser?.getIdToken(true);
      }
      await _synchronizeUser(refreshedUser);
    });
  }

  // Function Name: signOut
  // Description: Awaits application cleanup while the token is usable, signs out providers, and clears SMS and backend session state.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> signOut() async {
    await _runStrictAuthOperation(/* Function Name: _runStrictAuthOperation callback
     * Description: Runs pre-sign-out cleanup before signing out providers, clearing SMS state, and publishing an empty session.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of cleanup and provider sign-out.
     */() async {
      await _beforeSignOut?.call();
      if (_googleSignInInitialized) {
        await _googleSignIn.signOut();
      }
      await _requireFirebaseAuth().signOut();
      _clearSmsChallenge(notify: false);
      await _synchronizeUser(null);
    });
  }

  // Function Name: signOutForTest
  // Description: Exercises the strict sign-out cleanup order with an injected provider operation instead of a live Firebase session.
  // Parameters:
  // - providerSignOut (Future<void> Function()): Asynchronous provider sign-out boundary, injectable for testing.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  @visibleForTesting
  Future<void> signOutForTest(Future<void> Function() providerSignOut) async {
    await _runStrictAuthOperation(/* Function Name: _runStrictAuthOperation callback
     * Description: Runs shared pre-sign-out cleanup before the supplied provider sign-out operation.
     * Parameters:
     * - None.
     * Returns:
     * - Completion of cleanup and the provider-specific operation.
     */() async {
      await _beforeSignOut?.call();
      await providerSignOut();
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
      throw StateError('Sign in before deleting this account.');
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
      throw StateError(
        'For security, sign out and sign in again before deleting this account.',
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
        throw StateError('Google did not return an identity token.');
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
    _session = null;
    notifyListeners();
    await _runStrictAuthOperation(providerSignOut);
  }

  // Function Name: _runStrictAuthOperation
  // Description: Serializes bounded authentication work and publishes translated failures while rethrowing them to cleanup callers.
  // Parameters:
  // - operation (Future<void> Function()): Authentication operation run inside serialization and error handling.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _runStrictAuthOperation(
    Future<void> Function() operation,
  ) async {
    if (_isBusy) {
      throw StateError('Another authentication request is already running.');
    }
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation().timeout(_authenticationOperationTimeout);
    } on FirebaseAuthException catch (error) {
      final message = _messageForFirebaseError(error.code);
      _setError(message);
      throw StateError(message);
    } on GoogleSignInException catch (error) {
      final message = error.description ?? 'Google sign-in was not completed.';
      _setError(message);
      throw StateError(message);
    } on TimeoutException {
      const message =
          'Authentication timed out. Check the network and try again.';
      _setError(message);
      throw StateError(message);
    } on StateError catch (error) {
      _setError(error.message);
      rethrow;
    } catch (_) {
      const message = 'Authentication request failed. Please try again.';
      _setError(message);
      throw StateError(message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  // Function Name: _runAuthOperation
  // Description: Serializes authentication work, handles MFA challenges and provider errors, and always releases the busy state; an optional null timeout permits interactive sign-in.
  // Parameters:
  // - operation (Future<void> Function()): Authentication operation run inside serialization and error handling.
  // - timeout (Duration?): Authentication timeout; null waits without a time limit.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _runAuthOperation(
    Future<void> Function() operation, {
    Duration? timeout = _authenticationOperationTimeout,
  }) async {
    if (_isBusy) {
      return;
    }
    _isBusy = true;
    _errorMessage = null;
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
      _setError(_messageForFirebaseError(error.code));
    } on GoogleSignInException catch (error) {
      _setError(error.description ?? 'Google sign-in was not completed.');
    } on StateError catch (error) {
      _setError(error.message);
    } on TimeoutException {
      _setError('Authentication timed out. Check the network and try again.');
    } catch (_) {
      _setError('Authentication request failed. Please try again.');
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  // 함수이름: _synchronizeUser
  // 함수역할: Firebase 신원을 이메일 검증·MFA 상태와 조정하고 삭제된 신원과 오래된 응답을 제외한 뒤 인증된 백엔드 교환 결과만 세션으로 채택한다.
  // 매개변수:
  // - user (User?): 현재 또는 새로 복원된 Firebase 사용자
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _synchronizeUser(User? user) async {
    final generation = ++_sessionGeneration;
    final deletedSubject = _deletedFirebaseSubject;
    if (user != null && user.uid == deletedSubject) {
      _session = null;
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
    if (user == null || _emailVerificationRequired) {
      _session = null;
      notifyListeners();
      return;
    }

    try {
      final response = await apiClient
          .get(Uri.parse(ApiConfig.authSessionUrl))
          .timeout(_backendSessionTimeout);
      if (generation != _sessionGeneration) {
        return;
      }
      if (response.statusCode != 200) {
        throw StateError('Authenticated backend session could not be created.');
      }
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Authentication session is malformed.');
      }
      final session = AuthSession.fromJson(payload);
      if (!session.authenticated) {
        throw const FormatException('Backend session is not authenticated.');
      }
      _session = session;
      _errorMessage = null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Backend session handshake failed: ${error.runtimeType}: $error',
        );
      }
      if (generation == _sessionGeneration) {
        _session = null;
        _setError(
          resolveBackendSessionError(error, isEnglish: false),
          cause: error,
        );
      }
    } finally {
      if (generation == _sessionGeneration) {
        notifyListeners();
      }
    }
  }

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
      _session = null;
      _setError('Your secure session expired. Please sign in again.');
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
      throw StateError('Firebase authentication is unavailable.');
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
      _setError('SMS verification is unavailable in this beta build.');
      return;
    }
    final phoneHint = resolver.hints
        .whereType<PhoneMultiFactorInfo>()
        .firstOrNull;
    if (phoneHint == null) {
      _setError('No supported SMS second factor is available.');
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
      _setError(_messageForFirebaseError(error.code));
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
    _setError(_messageForFirebaseError(error.code));
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
  // 함수역할: 사용자용 인증 안내와 선택적 백엔드 오류 원인을 저장하고 구독 화면에 변경을 알린다.
  // 매개변수:
  // - message (String): 사용자에게 표시하거나 오류로 보존할 안내 문구
  // - cause (Object?): 언어별 안내에 사용할 원래 서버 세션 오류
  // 반환값:
  // - 없음.
  void _setError(String message, {Object? cause}) {
    _errorMessage = message;
    _backendSessionError = cause;
    notifyListeners();
  }

  // Function Name: _messageForFirebaseError
  // Description: Maps Firebase error codes to actionable sign-in, phone-verification, or MFA guidance with a general fallback.
  // Parameters:
  // - code (String): Firebase authentication error code.
  // Returns:
  // - String: Maps Firebase error codes to actionable sign-in, phone-verification, or MFA guidance with a general fallback.
  String _messageForFirebaseError(String code) => switch (code) {
    'invalid-email' => 'Enter a valid email address.',
    'invalid-credential' ||
    'user-not-found' ||
    'wrong-password' => 'The email or password is incorrect.',
    'email-already-in-use' => 'An account already uses this email address.',
    'credential-already-in-use' =>
      'This sign-in method belongs to another account. Sign out first to use it.',
    'weak-password' => 'Use a stronger password with at least six characters.',
    'too-many-requests' => 'Too many attempts. Please wait and try again.',
    'network-request-failed' => 'Check your network connection and try again.',
    'invalid-phone-number' => 'Enter a valid international phone number.',
    'invalid-verification-code' => 'The SMS verification code is incorrect.',
    'quota-exceeded' => 'The SMS quota is exhausted. Try again later.',
    'requires-recent-login' =>
      'Sign out and sign in again before changing MFA.',
    'operation-not-allowed' => 'This sign-in method is not enabled yet.',
    _ => 'Authentication request failed. Please try again.',
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
    _authSubscription?.cancel();
    apiClient.close();
    super.dispose();
  }
}
