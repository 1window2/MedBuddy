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

enum SmsChallengePurpose { phoneSignIn, mfaSignIn, mfaEnrollment }

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

  bool _isInitializing = true;
  @override
  bool get isInitializing => _isInitializing;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  AuthSession? _session;
  AuthSession? get session => _session;

  @override
  bool get isAuthenticated => _session != null;

  String? _signedInEmail;
  String? get signedInEmail => _signedInEmail;

  bool _emailVerificationRequired = false;
  bool get emailVerificationRequired => _emailVerificationRequired;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _configurationFailed = false;
  bool get configurationFailed => _configurationFailed;

  bool _initializationFailed = false;
  bool get initializationFailed => _initializationFailed;
  bool get phoneAuthenticationEnabled => AuthConfig.phoneAuthenticationEnabled;

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

  bool get smsCodeRequired => _smsVerificationId != null;
  String? get smsDestination => _smsDestination;
  SmsChallengePurpose? get smsChallengePurpose => _smsChallengePurpose;

  bool get canEnrollSmsMfa {
    if (!phoneAuthenticationEnabled) {
      return false;
    }
    final user = _firebaseAuth?.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) {
      return false;
    }
    return user.providerData.any(
      (provider) => provider.providerId != PhoneAuthProvider.PROVIDER_ID,
    );
  }

  bool get hasEnrolledSmsMfa => _hasEnrolledSmsMfa;

  AuthenticationControl._() {
    apiClient = AuthenticatedApiClient(
      tokenProvider: () async => await _firebaseAuth?.currentUser?.getIdToken(),
      onUnauthorized: _invalidateUnauthorizedSession,
    );
  }

  factory AuthenticationControl.development() {
    final control = AuthenticationControl._();
    control._session = _createLocalSession();
    control._isInitializing = false;
    return control;
  }

  static AuthenticationControl bootstrap() {
    final control = AuthenticationControl._();
    unawaited(control._initialize());
    return control;
  }

  Future<void> _initialize() async {
    _configurationFailed = false;
    _initializationFailed = false;
    try {
      ApiConfig.validate();
      AuthConfig.validate();
    } catch (_) {
      _configurationFailed = true;
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
        onError: (Object error, StackTrace stackTrace) {
          _setError('Authentication state could not be refreshed.');
        },
      );
      await _synchronizeUser(firebaseAuth.currentUser);
    } catch (_) {
      _initializationFailed = true;
      _session = null;
      _errorMessage =
          'MedBuddy could not initialize its secure services. Check the network and retry.';
    } finally {
      _finishInitialization();
    }
  }

  // Function Name: retryInitialization
  // Description:
  // - Repeats Firebase and App Check bootstrap after a recoverable startup
  //   failure without enabling an unauthenticated local fallback.
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
  // Description:
  // - Reuses the current Firebase identity to retry only the authenticated
  //   backend session handshake after connectivity is restored.
  // Returns:
  // - Completes after the session is synchronized or a bounded error is shown.
  Future<void> retryBackendSession() async {
    await _runAuthOperation(() async {
      final user = _requireFirebaseAuth().currentUser;
      if (user == null) {
        throw StateError('Sign in before retrying the secure session.');
      }
      await _synchronizeUser(user);
    });
  }

  void _finishInitialization() {
    _isInitializing = false;
    notifyListeners();
  }

  // 인증을 사용하지 않는 로컬 연동 테스트에서는 실행 옵션으로 기기별 사용자를 구분한다.
  static AuthSession _createLocalSession() {
    return AuthSession(
      userHash: PatientHash.normalizePatientHash(AuthConfig.localUserHash),
      authenticated: false,
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _runAuthOperation(() async {
      final firebaseAuth = _requireFirebaseAuth();
      final credential = await firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _synchronizeUser(credential.user ?? firebaseAuth.currentUser);
    });
  }

  Future<void> signInAnonymously() async {
    await _runAuthOperation(() async {
      final firebaseAuth = _requireFirebaseAuth();
      final credential = await firebaseAuth.signInAnonymously();
      await _synchronizeUser(credential.user ?? firebaseAuth.currentUser);
    });
  }

  Future<void> signInWithGoogle() async {
    await _runAuthOperation(() async {
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
    await _runAuthOperation(() async {
      await _requireFirebaseAuth().verifyPhoneNumber(
        phoneNumber: normalizedPhoneNumber,
        verificationCompleted: _completePhoneSignInAutomatically,
        verificationFailed: _handlePhoneVerificationFailure,
        codeSent: (verificationId, resendToken) {
          _setSmsChallenge(
            verificationId: verificationId,
            destination: normalizedPhoneNumber,
            purpose: SmsChallengePurpose.phoneSignIn,
          );
        },
        codeAutoRetrievalTimeout: (verificationId) {
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
    await _runAuthOperation(() async {
      final session = await user.multiFactor.getSession();
      await _requireFirebaseAuth().verifyPhoneNumber(
        multiFactorSession: session,
        phoneNumber: normalizedPhoneNumber,
        verificationCompleted: (_) {},
        verificationFailed: _handlePhoneVerificationFailure,
        codeSent: (verificationId, resendToken) {
          _setSmsChallenge(
            verificationId: verificationId,
            destination: normalizedPhoneNumber,
            purpose: SmsChallengePurpose.mfaEnrollment,
          );
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    });
  }

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
    await _runAuthOperation(() async {
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

  void cancelSmsChallenge() {
    _clearSmsChallenge();
  }

  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    await _runAuthOperation(() async {
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

  Future<bool> sendPasswordReset(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      _setError('Enter your email address first.');
      return false;
    }
    var sent = false;
    await _runAuthOperation(() async {
      await _requireFirebaseAuth().sendPasswordResetEmail(
        email: normalizedEmail,
      );
      sent = true;
    });
    return sent;
  }

  Future<void> resendEmailVerification() async {
    await _runAuthOperation(() async {
      final user = _requireFirebaseAuth().currentUser;
      if (user == null) {
        throw StateError('No signed-in user is available.');
      }
      await user.sendEmailVerification();
    });
  }

  Future<void> refreshEmailVerification() async {
    await _runAuthOperation(() async {
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

  Future<void> signOut() async {
    await _runAuthOperation(() async {
      if (_googleSignInInitialized) {
        await _googleSignIn.signOut();
      }
      await _requireFirebaseAuth().signOut();
      _clearSmsChallenge(notify: false);
      await _synchronizeUser(null);
    });
  }

  // 함수명: deleteCurrentUser
  // 역할:
  // - 서버의 MedBuddy 데이터 삭제가 끝난 뒤 Firebase 인증 계정을 삭제한다.
  // - 인증을 사용하지 않는 로컬 데모에서는 현재 로컬 세션을 그대로 유지한다.
  Future<void> deleteCurrentUser() async {
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      _session = _createLocalSession();
      notifyListeners();
      return;
    }
    final firebaseAuth = _requireFirebaseAuth();
    final user = firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('삭제할 로그인 계정이 없습니다.');
    }
    await user.delete();
    if (_googleSignInInitialized) {
      await _googleSignIn.signOut();
    }
    _clearSmsChallenge(notify: false);
    await _synchronizeUser(null);
  }

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

  Future<void> _synchronizeUser(User? user) async {
    final generation = ++_sessionGeneration;
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
    } catch (_) {
      if (generation == _sessionGeneration) {
        _session = null;
        _setError(
          'The secure MedBuddy server session could not be established.',
        );
      }
    } finally {
      if (generation == _sessionGeneration) {
        notifyListeners();
      }
    }
  }

  Future<void> _invalidateUnauthorizedSession() async {
    final firebaseAuth = _firebaseAuth;
    if (firebaseAuth == null) {
      return;
    }
    _session = null;
    _setError('Your secure session expired. Please sign in again.');
    await firebaseAuth.signOut();
  }

  FirebaseAuth _requireFirebaseAuth() {
    final firebaseAuth = _firebaseAuth;
    if (firebaseAuth == null) {
      throw StateError('Firebase authentication is unavailable.');
    }
    return firebaseAuth;
  }

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

  bool _requiresEmailVerification(User? user) {
    if (user == null || user.isAnonymous || user.emailVerified) {
      return false;
    }
    return user.providerData.any(
      (provider) => provider.providerId == EmailAuthProvider.PROVIDER_ID,
    );
  }

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
      verificationCompleted: (_) {},
      verificationFailed: _handlePhoneVerificationFailure,
      codeSent: (verificationId, resendToken) {
        _setSmsChallenge(
          verificationId: verificationId,
          destination: phoneHint.phoneNumber,
          purpose: SmsChallengePurpose.mfaSignIn,
        );
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

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

  void _handlePhoneVerificationFailure(FirebaseAuthException error) {
    _clearSmsChallenge(notify: false);
    _setError(_messageForFirebaseError(error.code));
  }

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

  void _clearSmsChallenge({bool notify = true}) {
    _smsVerificationId = null;
    _smsDestination = null;
    _smsChallengePurpose = null;
    _multiFactorResolver = null;
    if (notify) {
      notifyListeners();
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

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

  @override
  void dispose() {
    _sessionGeneration += 1;
    _authSubscription?.cancel();
    apiClient.close();
    super.dispose();
  }
}
