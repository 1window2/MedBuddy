// File Name: authentication_ui_boundary.dart
// Role: UI boundaries and helpers for sign-in, account creation, and email or SMS verification.
import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/app_language_control.dart';
import '../controls/authentication_control.dart';
import '../services/foreground_recovery_service.dart';
import '../theme/medbuddy_theme.dart';

// Class Name: AuthenticationUI
// Role: Represents sign-in methods and the account creation form.
// Responsibilities:
// - Holds the configuration consumed by the State responsible for sign-in methods and the account creation form.
// Attributes:
// - control (AuthenticationControl): Controller handling this screen's queries and update requests.
// - languageControl (AppLanguageControl?): Controller exposing and updating app language with change notifications.
class AuthenticationUI extends StatefulWidget {
  final AuthenticationControl control;
  final AppLanguageControl? languageControl;

  // Function Name: AuthenticationUI
  // Description: Initializes sign-in methods and the account creation form with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - control (AuthenticationControl): Controller handling this screen's queries and update requests.
  // - languageControl (AppLanguageControl?): Controller exposing and updating app language with change notifications.
  // Returns: Initialized AuthenticationUI instance.
  const AuthenticationUI({
    super.key,
    required this.control,
    this.languageControl,
  });

  // Function Name: createState
  // Description: Creates the state object that coordinates sign-in methods and the account creation form.
  // Parameters:
  // - None.
  // Returns: A new _AuthenticationUIState instance.
  @override
  State<AuthenticationUI> createState() => _AuthenticationUIState();
}

// 클래스명: _AuthenticationUIState
// 역할: 로그인 방식과 계정 생성 폼의 화면 상태를 관리한다.
// 주요 책임:
// - 화면이 유지 중이면 변경된 언어로 인증 화면을 다시 그린다.
// - 언어 컨트롤러에 한국어·영어 전환을 요청한다.
// - 이메일·비밀번호 검증 후 선택된 모드에 따라 계정 생성 또는 로그인을 요청한다.
// 속성:
// - _languageControl (AppLanguageControl): 앱 언어를 조회·변경하고 변경을 알리는 컨트롤러.
class _AuthenticationUIState extends State<AuthenticationUI>
    with WidgetsBindingObserver {
  late final ForegroundRecoveryService _sessionRecovery;
  bool _foreground = true;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _createAccount = false;
  bool _obscurePassword = true;
  late final AppLanguageControl _languageControl;
  late final bool _ownsLanguageControl;

  // Function Name: initState
  // Description: Connects a supplied language controller or creates an owned one, then subscribes to language changes.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _sessionRecovery = ForegroundRecoveryService(() async {
      if (!widget.control.shouldAutoRetryBackendSession) return true;
      if (widget.control.isBusy || widget.control.isInitializing) return false;
      await widget.control.retryBackendSession();
      return !widget.control.shouldAutoRetryBackendSession;
    });
    WidgetsBinding.instance.addObserver(this);
    widget.control.addListener(_handleAuthenticationChanged);
    _handleAuthenticationChanged();
    _ownsLanguageControl = widget.languageControl == null;
    _languageControl =
        widget.languageControl ?? AppLanguageControl(loadPersisted: false);
    _languageControl.addListener(_handleLanguageChanged);
  }

  // Function Name: dispose
  // Description: Releases _emailController, _passwordController, _languageControl and detaches this screen from active updates.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void dispose() {
    widget.control.removeListener(_handleAuthenticationChanged);
    WidgetsBinding.instance.removeObserver(this);
    _sessionRecovery.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _languageControl.removeListener(_handleLanguageChanged);
    if (_ownsLanguageControl) {
      _languageControl.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AuthenticationUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.control != widget.control) {
      oldWidget.control.removeListener(_handleAuthenticationChanged);
      _sessionRecovery.stop();
      widget.control.addListener(_handleAuthenticationChanged);
      _handleAuthenticationChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _sessionRecovery.stop();
    _handleAuthenticationChanged();
  }

  // Navigator가 유지하는 로그인 화면도 처리 중 상태와 인증 오류를 직접 갱신한다.
  void _handleAuthenticationChanged() {
    // Auth notifications can arrive during a build: defer the retry mutation.
    Future.microtask(() {
      if (!mounted) return;
      setState(() {});
      if (_foreground && widget.control.shouldAutoRetryBackendSession) {
        _sessionRecovery.start();
      } else {
        _sessionRecovery.stop();
      }
    });
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 로그인 방식과 계정 생성 폼 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 로그인 방식과 계정 생성 폼에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final text = _AuthenticationText(_languageControl.language);
    final errorMessage = control.errorMessageForLanguage(
      isEnglish: text.isEnglish,
    );
    if (control.initializationFailed) {
      return _AuthenticationScaffold(
        languageControl: _languageControl,
        isBusy: control.isBusy,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    errorMessage ?? text.servicesUnavailable,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key(
                      'authentication-initialization-retry-button',
                    ),
                    onPressed: control.isBusy
                        ? null
                        : control.retryInitialization,
                    icon: const Icon(Icons.refresh),
                    label: Text(text.retryStartup),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (control.configurationFailed) {
      return _AuthenticationScaffold(
        languageControl: _languageControl,
        isBusy: control.isBusy,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                errorMessage ?? text.servicesUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ),
      );
    }
    if (control.emailVerificationRequired) {
      return _EmailVerificationView(
        control: control,
        languageControl: _languageControl,
        onSignedOut: _showSignInAfterVerification,
      );
    }
    if (control.smsCodeRequired &&
        control.smsChallengePurpose != SmsChallengePurpose.mfaEnrollment) {
      return _SmsCodeView(control: control, languageControl: _languageControl);
    }

    return _AuthenticationScaffold(
      languageControl: _languageControl,
      isBusy: control.isBusy,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'MedBuddy',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: MedBuddyColors.primary,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _createAccount
                              ? text.createAccountTitle
                              : text.signIn,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: text.email,
                            border: const OutlineInputBorder(),
                          ),
                          // Function Name: build.validator callback
                          // Description: Validates this form value using `(value ?? '').trim().contains('@') ? null : text.invalidEmail`.
                          // Parameters:
                          // - value (inferred by callback contract): Input to validate, normalize, display, or pass through a selection callback.
                          // Returns: Validation message when invalid; null when valid.
                          validator: (value) =>
                              (value ?? '').trim().contains('@')
                              ? null
                              : text.invalidEmail,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: _createAccount
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: text.password,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? text.showPassword
                                  : text.hidePassword,
                              // Function Name: build.onPressed callback
                              // Description: Connects sign-in methods and the account creation form to the captured operation `setState(() => _obscurePassword = !_obscurePassword)`.
                              // Parameters:
                              // - None.
                              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                              onPressed: () => setState(
                                // Function Name: build.setState callback
                                // Description: Updates the local input or request state for sign-in methods and the account creation form: `_obscurePassword = !_obscurePassword`.
                                // Parameters:
                                // - None.
                                // Returns: No payload; applies the captured state changes.
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          // Function Name: build.validator callback
                          // Description: Validates this form value using `(value ?? '').length >= 6 ? null : text.invalidPassword`.
                          // Parameters:
                          // - value (inferred by callback contract): Input to validate, normalize, display, or pass through a selection callback.
                          // Returns: Validation message when invalid; null when valid.
                          validator: (value) => (value ?? '').length >= 6
                              ? null
                              : text.invalidPassword,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            errorMessage,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        if (control.canRetryBackendSession) ...[
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            key: const Key('backend-session-retry-button'),
                            onPressed: control.isBusy
                                ? null
                                : control.retryBackendSession,
                            icon: const Icon(Icons.sync),
                            label: Text(text.retrySecureSession),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: control.isBusy ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            backgroundColor: MedBuddyColors.primary,
                          ),
                          child: control.isBusy
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _createAccount
                                      ? text.createAccount
                                      : text.signIn,
                                ),
                        ),
                        if (!_createAccount)
                          TextButton(
                            onPressed: control.isBusy
                                ? null
                                : _sendPasswordReset,
                            child: Text(text.forgotPassword),
                          ),
                        TextButton(
                          onPressed: control.isBusy
                              ? null
                              // Function Name: build.setState callback
                              // Description: Updates the local input or request state for sign-in methods and the account creation form: `_createAccount = !_createAccount`.
                              // Parameters:
                              // - None.
                              // Returns: No payload; applies the captured state changes.
                              // Function Name: build.onPressed callback
                              // Description: Connects sign-in methods and the account creation form to the captured operation `setState(() {_createAccount = !_createAccount;})`.
                              // Parameters:
                              // - None.
                              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                              : () => setState(() {
                                  _createAccount = !_createAccount;
                                }),
                          child: Text(
                            _createAccount
                                ? text.alreadyHaveAccount
                                : text.newToMedBuddy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(text.or),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: control.isBusy
                              ? null
                              : control.signInWithGoogle,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: Text(text.continueWithGoogle),
                        ),
                        if (control.phoneAuthenticationEnabled) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: control.isBusy
                                ? null
                                : _startPhoneSignIn,
                            icon: const Icon(Icons.sms_outlined),
                            label: Text(text.continueWithPhone),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: control.isBusy ? null : _continueAsGuest,
                          icon: const Icon(Icons.person_outline),
                          label: Text(text.continueAsGuest),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (control.isBusy)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color.fromRGBO(0, 0, 0, 0.32),
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      label: text.processing,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 20,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(text.processing),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Function Name: _handleLanguageChanged
  // Description: Rebuilds the mounted authentication screen after a language change.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  void _handleLanguageChanged() {
    if (mounted) {
      // Function Name: _handleLanguageChanged.setState callback
      // Description: Intentionally leaves captured values unchanged; the caller controls rebuilding or disables this interaction.
      // Parameters:
      // - None.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      setState(() {});
    }
  }

  // 인증에서 돌아오면 가입 모드와 비밀번호만 비우고 입력한 이메일·언어는 유지한다.
  void _showSignInAfterVerification() {
    if (!mounted) return;
    _passwordController.clear();
    setState(() => _createAccount = false);
  }

  // Function Name: _submit
  // Description: Validates the email and password, then creates an account or signs in according to the selected mode.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_createAccount) {
      await widget.control.createAccount(
        email: _emailController.text,
        password: _passwordController.text,
        language: _languageControl.language,
      );
      return;
    }
    await widget.control.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  // Function Name: _sendPasswordReset
  // Description: Requests a password reset for the entered email and reports successful delivery.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _sendPasswordReset() async {
    final sent = await widget.control.sendPasswordReset(
      _emailController.text,
      language: _languageControl.language,
    );
    if (!mounted || !sent) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _AuthenticationText(_languageControl.language).passwordResetSent,
          ),
        ),
      );
  }

  // Function Name: _startPhoneSignIn
  // Description: Collects an international phone number and starts SMS verification unless canceled.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _startPhoneSignIn() async {
    final text = _AuthenticationText(_languageControl.language);
    final phoneController = TextEditingController(text: '+82');
    final phoneNumber = await showDialog<String>(
      context: context,
      // Function Name: _startPhoneSignIn.builder callback
      // Description: Composes sign-in methods and the account creation form with Text, InputDecoration for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context) => AlertDialog(
        title: Text(text.phoneSignIn),
        content: TextField(
          controller: phoneController,
          autofocus: true,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: text.phoneNumber,
            hintText: '+821012345678',
          ),
        ),
        actions: [
          TextButton(
            // Function Name: _startPhoneSignIn.onPressed callback
            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
            // Parameters:
            // - None.
            // Returns: No callback payload; any selection is delivered through the route result.
            onPressed: () => Navigator.pop(context),
            child: Text(text.cancel),
          ),
          FilledButton(
            // Function Name: _startPhoneSignIn.onPressed callback
            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, phoneController.text)`.
            // Parameters:
            // - None.
            // Returns: No callback payload; any selection is delivered through the route result.
            onPressed: () => Navigator.pop(context, phoneController.text),
            child: Text(text.sendCode),
          ),
        ],
      ),
    );
    phoneController.dispose();
    if (phoneNumber == null || !mounted) {
      return;
    }
    await widget.control.startPhoneSignIn(phoneNumber);
  }

  // Function Name: _continueAsGuest
  // Description: Requests anonymous sign-in only after consent to temporary-account data limitations.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _continueAsGuest() async {
    final text = _AuthenticationText(_languageControl.language);
    final accepted = await showDialog<bool>(
      context: context,
      // Function Name: _continueAsGuest.builder callback
      // Description: Composes sign-in methods and the account creation form with the current parent constraints for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context) => AlertDialog(
        title: Text(text.guestConfirmationTitle),
        content: Text(text.guestConfirmationMessage),
        actions: [
          TextButton(
            // Function Name: _continueAsGuest.onPressed callback
            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, false)`.
            // Parameters:
            // - None.
            // Returns: No callback payload; any selection is delivered through the route result.
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.cancel),
          ),
          FilledButton(
            // Function Name: _continueAsGuest.onPressed callback
            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, true)`.
            // Parameters:
            // - None.
            // Returns: No callback payload; any selection is delivered through the route result.
            onPressed: () => Navigator.pop(context, true),
            child: Text(text.continueLabel),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await widget.control.signInAnonymously();
    }
  }
}

// 클래스명: _AuthenticationText
// 역할: 로그인, 계정 생성 및 이메일·문자 인증에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 앱에서 선택한 언어로 로그인 화면의 문구를 제공한다.
// - 검증·게스트 동의·진행 상태 안내를 간결하게 유지한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _AuthenticationText {
  final String language;

  // Function Name: _AuthenticationText
  // Description: Stores the language used to select localized wording for sign-in, account creation, and email or SMS verification.
  // Parameters:
  // - language (String): Language code selecting visible wording.
  // Returns: Initialized _AuthenticationText instance.
  const _AuthenticationText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';
  // 함수이름: _isEnglish
  // 함수역할: 문구 제공 객체의 영어 선택 상태를 그대로 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _isEnglish => isEnglish;

  // Function Name: signIn
  // Description: Provides localized wording for "Sign in" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get signIn => _isEnglish ? 'Sign in' : '로그인';
  // Function Name: createAccountTitle
  // Description: Provides localized wording for "Create a secure account" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get createAccountTitle =>
      _isEnglish ? 'Create a secure account' : '안전한 계정 만들기';
  // Function Name: email
  // Description: Provides localized wording for "Email" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get email => _isEnglish ? 'Email' : '이메일';
  // Function Name: password
  // Description: Provides localized wording for "Password" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get password => _isEnglish ? 'Password' : '비밀번호';
  // Function Name: showPassword
  // Description: Provides localized wording for "Show password" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get showPassword => _isEnglish ? 'Show password' : '비밀번호 표시';
  // Function Name: hidePassword
  // Description: Provides localized wording for "Hide password" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get hidePassword => _isEnglish ? 'Hide password' : '비밀번호 숨기기';
  // Function Name: invalidEmail
  // Description: Provides localized wording for "Enter a valid email address." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get invalidEmail =>
      _isEnglish ? 'Enter a valid email address.' : '올바른 이메일 주소를 입력해 주세요.';
  // Function Name: invalidPassword
  // Description: Provides localized wording for "Use at least six characters." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get invalidPassword =>
      _isEnglish ? 'Use at least six characters.' : '비밀번호는 6자 이상 입력해 주세요.';
  // Function Name: retrySecureSession
  // Description: Provides localized wording for "Retry secure session" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get retrySecureSession =>
      _isEnglish ? 'Retry secure session' : '보안 세션 다시 연결';
  // Function Name: createAccount
  // Description: Provides localized wording for "Create account" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get createAccount => _isEnglish ? 'Create account' : '회원가입';
  // Function Name: forgotPassword
  // Description: Provides localized wording for "Forgot password?" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get forgotPassword => _isEnglish ? 'Forgot password?' : '비밀번호 찾기';
  // Function Name: alreadyHaveAccount
  // Description: Provides localized wording for "Already have an account? Sign in" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get alreadyHaveAccount =>
      _isEnglish ? 'Already have an account? Sign in' : '이미 계정이 있으신가요? 로그인';
  // Function Name: newToMedBuddy
  // Description: Provides localized wording for "New to MedBuddy? Create an account" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get newToMedBuddy => _isEnglish
      ? 'New to MedBuddy? Create an account'
      : 'MedBuddy가 처음이신가요? 회원가입';
  // Function Name: or
  // Description: Selects the localized separator between alternative sign-in methods.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get or => _isEnglish ? 'or' : '또는';
  // Function Name: continueWithGoogle
  // Description: Provides localized wording for "Continue with Google" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get continueWithGoogle =>
      _isEnglish ? 'Continue with Google' : 'Google로 계속하기';
  // Function Name: continueAsGuest
  // Description: Provides localized wording for "Continue as guest" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get continueAsGuest =>
      _isEnglish ? 'Continue as guest' : '회원가입 없이 계속하기';
  // Function Name: changeLanguage
  // Description: Provides localized wording for "Change language" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get changeLanguage => _isEnglish ? 'Change language' : '언어 변경';
  // Function Name: processing
  // Description: Provides localized wording for "Please wait…" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get processing => _isEnglish ? 'Please wait…' : '처리 중입니다…';
  // Function Name: guestConfirmationTitle
  // Description: Provides localized wording for "Continue as guest?" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get guestConfirmationTitle =>
      _isEnglish ? 'Continue as guest?' : '게스트로 계속할까요?';
  // Function Name: guestConfirmationMessage
  // Description: Provides localized wording for "Guest access is tied to this temporary account. Sign in with a" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get guestConfirmationMessage => _isEnglish
      ? 'Guest access is tied to this temporary account. Sign in with a '
            'permanent account before changing devices or clearing app data.'
      : '게스트 데이터는 이 임시 계정에만 연결됩니다. 기기를 변경하거나 '
            '앱 데이터를 지우기 전에 정식 계정으로 로그인해 주세요.';
  // Function Name: cancel
  // Description: Provides localized wording for "Cancel" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get cancel => _isEnglish ? 'Cancel' : '취소';
  // Function Name: continueLabel
  // Description: Provides localized wording for "Continue" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get continueLabel => _isEnglish ? 'Continue' : '계속';

  // 인증 중간 화면도 로그인 화면과 같은 언어를 사용한다.
  String get verifyEmail => _isEnglish ? 'Verify your email' : '이메일을 인증해 주세요';
  String verificationEmailSent(String? email) => _isEnglish
      ? 'A verification email was sent to ${email ?? 'your email address'}.'
      : '${email ?? '입력한 이메일 주소'}로 인증 메일을 보냈어요.';
  String get automaticEmailVerification => _isEnglish
      ? 'Open the link in your email, then return to the app to sign in automatically.'
      : '메일의 인증 링크를 누른 뒤 앱으로 돌아오면 자동으로 로그인됩니다.';
  String get checkEmailVerification =>
      _isEnglish ? 'Check verification status' : '인증 상태 다시 확인';
  String get checkingEmailVerification =>
      _isEnglish ? 'Checking verification…' : '인증 확인 중…';
  String get backToSignIn => _isEnglish ? 'Back to sign in' : '로그인 화면으로 돌아가기';
  String get resendEmail =>
      _isEnglish ? 'Resend verification email' : '인증 메일 다시 보내기';
  String get passwordResetSent => _isEnglish
      ? 'Password reset instructions were sent by email.'
      : '비밀번호 재설정 메일을 보냈습니다.';
  String get servicesUnavailable => _isEnglish
      ? 'MedBuddy secure services are temporarily unavailable.'
      : '지금은 로그인 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
  String get retryStartup => _isEnglish ? 'Retry secure startup' : '다시 연결';
  String get continueWithPhone =>
      _isEnglish ? 'Continue with phone' : '전화번호로 계속하기';
  String get phoneSignIn => _isEnglish ? 'Phone sign-in' : '전화번호로 로그인';
  String get phoneNumber =>
      _isEnglish ? 'International phone number' : '전화번호 (국가번호 포함)';
  String get sendCode => _isEnglish ? 'Send code' : '인증번호 보내기';
  String get enterCode =>
      _isEnglish ? 'Enter verification code' : '인증번호를 입력해 주세요';
  String codeSent(String? phone) => _isEnglish
      ? 'A code was sent to ${phone ?? 'your phone'}.'
      : '${phone ?? '입력한 전화번호'}로 인증번호를 보냈습니다.';
  String get smsCode => _isEnglish ? 'SMS code' : '문자 인증번호';
  String get verify => _isEnglish ? 'Verify' : '인증하기';
}

// 인증 단계가 바뀌어도 언어 버튼 위치를 유지하고 본문과 겹치지 않게 한다.
class _AuthenticationScaffold extends StatelessWidget {
  final AppLanguageControl languageControl;
  final bool isBusy;
  final Widget body;
  final VoidCallback? onBack;

  const _AuthenticationScaffold({
    required this.languageControl,
    required this.isBusy,
    required this.body,
    this.onBack,
  });

  // 언어 아이콘을 누를 때만 선택창을 열고, 닫기만 하면 기존 설정을 유지한다.
  Future<void> _selectLanguage(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: MedBuddyColors.surface,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  '언어 / Language',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: languageControl.language,
                onChanged: (value) => Navigator.pop(sheetContext, value),
                child: Column(
                  children: [
                    for (final option in const {
                      'ko': '한국어',
                      'en': 'English',
                    }.entries)
                      RadioListTile<String>(
                        key: ValueKey('authentication-language-${option.key}'),
                        value: option.key,
                        selected: languageControl.language == option.key,
                        activeColor: MedBuddyColors.primary,
                        selectedTileColor: MedBuddyColors.successSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(
                          option.value,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || selected == null) return;
    await languageControl.setLanguage(selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    key: const Key('authentication-back'),
                    tooltip: _AuthenticationText(
                      languageControl.language,
                    ).backToSignIn,
                    onPressed: isBusy ? null : onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                const Spacer(),
                IconButton(
                  key: const Key('authentication-language-toggle'),
                  tooltip: '언어 / Language',
                  onPressed: isBusy ? null : () => _selectLanguage(context),
                  icon: const Icon(Icons.language),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    ),
  );
}

// Class Name: _SmsCodeView
// Role: Represents six-digit SMS code entry, verification, and cancellation.
// Responsibilities:
// - Holds the configuration consumed by the State responsible for six-digit SMS code entry, verification, and cancellation.
// Attributes:
// - control (AuthenticationControl): Controller handling this screen's queries and update requests.
class _SmsCodeView extends StatefulWidget {
  final AuthenticationControl control;
  final AppLanguageControl languageControl;

  // Function Name: _SmsCodeView
  // Description: Initializes six-digit SMS code entry, verification, and cancellation with the supplied configuration.
  // Parameters:
  // - control (AuthenticationControl): Controller handling this screen's queries and update requests.
  // - languageControl (AppLanguageControl): Language shared with sign-in and account creation.
  // Returns: Initialized _SmsCodeView instance.
  const _SmsCodeView({required this.control, required this.languageControl});

  // Function Name: createState
  // Description: Creates the state object that coordinates six-digit SMS code entry, verification, and cancellation.
  // Parameters:
  // - None.
  // Returns: A new _SmsCodeViewState instance.
  @override
  State<_SmsCodeView> createState() => _SmsCodeViewState();
}

// 클래스명: _SmsCodeViewState
// 역할: 문자로 받은 6자리 인증번호 입력과 제출·취소의 화면 상태를 관리한다.
// 주요 책임:
// - 문자로 받은 6자리 인증번호 입력과 제출·취소에 필요한 상태 변경과 사용자 동작을 연결한다.
class _SmsCodeViewState extends State<_SmsCodeView> {
  final _codeController = TextEditingController();

  // Function Name: dispose
  // Description: Releases _codeController and detaches this screen from active updates.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 문자로 받은 6자리 인증번호 입력과 제출·취소 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 문자로 받은 6자리 인증번호 입력과 제출·취소에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final text = _AuthenticationText(widget.languageControl.language);
    final errorMessage = control.errorMessageForLanguage(
      isEnglish: text.isEnglish,
    );
    return _AuthenticationScaffold(
      languageControl: widget.languageControl,
      isBusy: control.isBusy,
      body: _ScrollableAuthenticationBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.sms_outlined,
              size: 64,
              color: MedBuddyColors.primary,
            ),
            const SizedBox(height: 20),
            Text(
              text.enterCode,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              text.codeSent(control.smsDestination),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: InputDecoration(
                labelText: text.smsCode,
                border: const OutlineInputBorder(),
              ),
            ),
            if (errorMessage != null)
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: control.isBusy
                  ? null
                  // Function Name: build.onPressed callback
                  // Description: Connects six-digit SMS code entry, verification, and cancellation to the captured operation `control.submitSmsCode(_codeController.text)`.
                  // Parameters:
                  // - None.
                  // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                  : () => control.submitSmsCode(_codeController.text),
              child: Text(text.verify),
            ),
            TextButton(
              onPressed: control.isBusy ? null : control.cancelSmsChallenge,
              child: Text(text.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _EmailVerificationView
// 역할: 인증 메일 재전송과 이메일 인증 상태 재확인을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 인증 메일 재전송과 이메일 인증 상태 재확인 위젯을 구성한다.
// 속성:
// - control (AuthenticationControl): 화면의 조회·변경 요청을 처리할 컨트롤러.
class _EmailVerificationView extends StatefulWidget {
  final AuthenticationControl control;
  final AppLanguageControl languageControl;
  final VoidCallback onSignedOut;

  // Function Name: _EmailVerificationView
  // Description: Initializes verification-email resending and email verification status checks with the supplied configuration.
  // Parameters:
  // - control (AuthenticationControl): Controller handling this screen's queries and update requests.
  // - languageControl (AppLanguageControl): Language used for both the screen and email dispatch.
  // - onSignedOut (VoidCallback): Restores the sign-in form after successful sign-out.
  // Returns: Initialized _EmailVerificationView instance.
  const _EmailVerificationView({
    required this.control,
    required this.languageControl,
    required this.onSignedOut,
  });

  @override
  State<_EmailVerificationView> createState() => _EmailVerificationViewState();
}

// 인증 재확인만 진행 표시로 구분하고, 로그인 복귀 실패는 같은 화면에서 안내한다.
class _EmailVerificationViewState extends State<_EmailVerificationView>
    with WidgetsBindingObserver {
  bool _checkingVerification = false;
  Timer? _verificationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleVerificationChecks();
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 다른 기기에서 메일을 인증해도 감지하되, 백그라운드에서는 조회하지 않는다.
  void _scheduleVerificationChecks() {
    _verificationTimer?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _verificationTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_checkAutomatically()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _verificationTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _scheduleVerificationChecks();
      unawaited(_checkAutomatically());
    }
  }

  // 수동 확인·재전송과 요청을 겹치지 않고 미인증 결과는 조용히 유지한다.
  Future<void> _checkAutomatically() async {
    if (!mounted ||
        widget.control.isBusy ||
        !widget.control.emailVerificationRequired ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    await widget.control.refreshEmailVerification(showPendingMessage: false);
  }

  Future<void> _checkVerification() async {
    if (widget.control.isBusy || _checkingVerification) return;
    setState(() => _checkingVerification = true);
    try {
      await widget.control.refreshEmailVerification();
    } finally {
      if (mounted) setState(() => _checkingVerification = false);
    }
  }

  // 계정은 삭제하지 않고 세션만 종료한다. 실패 안내는 컨트롤러가 제공한다.
  Future<void> _returnToSignIn() async {
    if (widget.control.isBusy) return;
    try {
      await widget.control.signOut();
      widget.onSignedOut();
    } on StateError {
      // 로그아웃 실패 시 인증 화면과 오류 안내를 유지한다.
    }
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 인증 메일 재전송과 이메일 인증 상태 재확인 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 인증 메일 재전송과 이메일 인증 상태 재확인에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final languageControl = widget.languageControl;
    final text = _AuthenticationText(languageControl.language);
    final errorMessage = control.errorMessageForLanguage(
      isEnglish: text.isEnglish,
    );
    return _AuthenticationScaffold(
      languageControl: languageControl,
      isBusy: control.isBusy,
      onBack: _returnToSignIn,
      body: _ScrollableAuthenticationBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.mark_email_unread_outlined,
              size: 64,
              color: MedBuddyColors.primary,
            ),
            const SizedBox(height: 20),
            Text(
              text.verifyEmail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              text.verificationEmailSent(control.signedInEmail),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(text.automaticEmailVerification, textAlign: TextAlign.center),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // 자동 로그인이 기본이며 재확인은 실패에 대비한 보조 동작으로 남긴다.
            Align(
              child: TextButton.icon(
                key: const Key('email-verification-check'),
                onPressed: control.isBusy ? null : _checkVerification,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: _checkingVerification
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                label: Text(
                  _checkingVerification
                      ? text.checkingEmailVerification
                      : text.checkEmailVerification,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            TextButton(
              onPressed: control.isBusy
                  ? null
                  : () => control.resendEmailVerification(
                      language: languageControl.language,
                    ),
              child: Text(text.resendEmail),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _ScrollableAuthenticationBody
// 역할: 키보드와 큰 글씨에서도 접근 가능한 너비 420 제한 인증 본문을 담당한다.
// 주요 책임:
// - 인증 내용을 읽기 좋은 최대 너비로 제한한다.
// - 남은 화면 높이를 채우되 공간이 부족하면 세로 스크롤을 제공한다.
// 속성:
// - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
class _ScrollableAuthenticationBody extends StatelessWidget {
  final Widget child;

  // 함수이름: _ScrollableAuthenticationBody
  // 함수역할: 키보드와 큰 글씨에서도 접근 가능한 너비 420 제한 인증 본문에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
  // 반환값: 입력 설정이 반영된 _ScrollableAuthenticationBody 인스턴스.
  const _ScrollableAuthenticationBody({required this.child});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 키보드와 큰 글씨에서도 접근 가능한 너비 420 제한 인증 본문 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 키보드와 큰 글씨에서도 접근 가능한 너비 420 제한 인증 본문에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        // 함수이름: build.builder callback
        // 함수역할: 키보드와 큰 글씨에서도 접근 가능한 너비 420 제한 인증 본문에 EdgeInsets.symmetric, BoxConstraints을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (context, constraints) {
          const horizontalPadding = 32.0;
          const verticalPadding = 24.0;
          final minimumHeight = constraints.maxHeight > verticalPadding * 2
              ? constraints.maxHeight - verticalPadding * 2
              : 0.0;

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minimumHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
