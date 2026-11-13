// File Name: authentication_ui_boundary.dart
// Role: UI boundaries and helpers for sign-in, account creation, and email or SMS verification.
import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/app_language_control.dart';
import '../controls/authentication_control.dart';
import '../entities/user_setting_entity.dart';
import '../services/foreground_recovery_service.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_confirm_dialog.dart';
import '../widgets/medbuddy_wordmark.dart';
import '../widgets/keep_words_text.dart';

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

  // 함수이름: initState
  // 함수역할: 입력·언어·인증 상태를 연결하고 세션 복구 및 앱 생명주기 변화를 관찰한다. 외부 언어 제어기가 없으면 화면 소유 제어기를 만든다.
  // 매개변수: 없음.
  // 반환값: 없음.
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

  // 함수이름: dispose
  // 함수역할: 인증·언어·복구 상태 리스너와 생명주기 관찰을 해제하고 입력 제어기 및 화면이 소유한 언어 제어기를 정리한다.
  // 매개변수: 없음.
  // 반환값: 없음.
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

  // 함수이름: didUpdateWidget
  // 함수역할: 인증 제어기가 교체되면 이전 감시와 복구 시도를 멈추고 새 제어기의 상태를 반영한다.
  // 매개변수: oldWidget (AuthenticationUI): 이전 화면 설정.
  // 반환값: 없음.
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

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 백그라운드에서는 세션 복구를 멈추고 현재 인증 상태에 따라 복구 필요성을 다시 판단한다.
  // 매개변수: state (AppLifecycleState): 새 앱 상태.
  // 반환값: 없음.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _sessionRecovery.stop();
    _handleAuthenticationChanged();
  }

  // 함수이름: _handleAuthenticationChanged
  // 함수역할: 빌드 중 알림도 안전하게 다음 마이크로태스크로 미뤄 화면과 전경 세션 복구 상태를 갱신한다.
  // 매개변수: 없음.
  // 반환값: 없음. 이미 해제된 화면은 무시한다.
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
                  KeepWordsText(
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
                    label: KeepWordsText(text.retryStartup),
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
              child: KeepWordsText(
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
      showWordmark: true,
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
                        KeepWordsText(
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
                          KeepWordsText(
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
                            label: KeepWordsText(text.retrySecureSession),
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
                            child: KeepWordsText(text.forgotPassword),
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
                          child: KeepWordsText(
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
                          label: KeepWordsText(text.continueWithGoogle),
                        ),
                        if (control.phoneAuthenticationEnabled) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: control.isBusy
                                ? null
                                : _startPhoneSignIn,
                            icon: const Icon(Icons.sms_outlined),
                            label: KeepWordsText(text.continueWithPhone),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: control.isBusy ? null : _continueAsGuest,
                          icon: const Icon(Icons.person_outline),
                          label: KeepWordsText(text.continueAsGuest),
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
                              KeepWordsText(text.processing),
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

  // 함수이름: _showSignInAfterVerification
  // 함수역할: 인증 화면에서 돌아오면 이메일·언어는 유지하고 비밀번호와 가입 모드만 초기화한다.
  // 매개변수: 없음.
  // 반환값: 없음. 화면이 해제되었으면 무시한다.
  void _showSignInAfterVerification() {
    if (!mounted) return;
    _passwordController.clear();
    setState(() => _createAccount = false);
  }

  // 함수이름: _submit
  // 함수역할: 이메일·비밀번호 검증을 통과하면 선택 모드에 따라 계정을 생성하거나 로그인한다. 검증 실패 시 요청하지 않는다.
  // 매개변수: 없음.
  // 반환값: 인증 요청 처리가 완료되는 Future<void>.
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

  // 함수이름: _sendPasswordReset
  // 함수역할: 현재 언어로 비밀번호 재설정 메일을 요청하고 화면이 유지되고 전송이 성공했을 때 안내한다.
  // 매개변수: 없음.
  // 반환값: 재설정 요청과 결과 안내 완료.
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
          content: KeepWordsText(
            _AuthenticationText(_languageControl.language).passwordResetSent,
          ),
        ),
      );
  }

  // 함수이름: _startPhoneSignIn
  // 함수역할: 국가번호가 포함된 전화번호를 입력받아 문자 인증을 시작하며 취소 시 요청하지 않고 입력 제어기를 정리한다.
  // 매개변수: 없음.
  // 반환값: 번호 입력과 인증 시작 처리 완료.
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
        title: KeepWordsText(text.phoneSignIn),
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
            child: KeepWordsText(text.sendCode),
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
    final accepted = await showMedBuddyConfirmDialog(
      context,
      title: text.guestConfirmationTitle,
      message: text.guestConfirmationMessage,
      cancelLabel: text.cancel,
      confirmLabel: text.continueLabel,
    );
    if (accepted && mounted) {
      await widget.control.signInAnonymously();
    }
  }
}

// Class Name: _AuthenticationText
// Role: Localized authentication copy.
// Responsibilities: Supplies labels and validation, guest-consent and verification messages using the shared language rule.
// Attributes: language (String): selected language code.
class _AuthenticationText {
  final String language;

  // Function Name: _AuthenticationText
  // Description: Stores the language used to select localized wording for sign-in, account creation, and email or SMS verification.
  // Parameters:
  // - language (String): Language code selecting visible wording.
  // Returns: Initialized _AuthenticationText instance.
  const _AuthenticationText(this.language);

  // Function Name: isEnglish
  // Description: Uses the shared language-code rule to select English authentication text.
  // Parameters: None.
  // Returns: True for an English language code.
  bool get isEnglish => isEnglishLanguage(language);
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

  // 함수이름: verifyEmail
  // 함수역할: 이메일 인증 요청 제목에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get verifyEmail => _isEnglish ? 'Verify your email' : '이메일을 인증해 주세요';
  // 함수이름: verificationEmailSent
  // 함수역할: 인증 메일의 수신 주소를 현재 언어의 발송 안내에 넣는다.
  // 매개변수: email (String?): 수신 주소; null이면 일반 주소 표현.
  // 반환값: 주소가 포함된 발송 안내.
  String verificationEmailSent(String? email) => _isEnglish
      ? 'A verification email was sent to ${email ?? 'your email address'}.'
      : '${email ?? '입력한 이메일 주소'}로 인증 메일을 보냈어요.';
  // 함수이름: automaticEmailVerification
  // 함수역할: 메일 링크를 연 뒤 앱으로 복귀하는 자동 인증 안내에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get automaticEmailVerification => _isEnglish
      ? 'Open the link in your email, then return to the app to sign in automatically.'
      : '메일의 인증 링크를 누른 뒤 앱으로 돌아오면 자동으로 로그인됩니다.';
  // 함수이름: checkEmailVerification
  // 함수역할: 인증 상태 수동 재확인 버튼에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get checkEmailVerification =>
      _isEnglish ? 'Check verification status' : '인증 상태 다시 확인';
  // 함수이름: checkingEmailVerification
  // 함수역할: 인증 확인 진행 상태에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get checkingEmailVerification =>
      _isEnglish ? 'Checking verification…' : '인증 확인 중…';
  // 함수이름: backToSignIn
  // 함수역할: 로그인 화면 복귀 버튼에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get backToSignIn => _isEnglish ? 'Back to sign in' : '로그인 화면으로 돌아가기';
  // 함수이름: resendEmail
  // 함수역할: 인증 메일 재전송 버튼에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get resendEmail =>
      _isEnglish ? 'Resend verification email' : '인증 메일 다시 보내기';
  // 함수이름: passwordResetSent
  // 함수역할: 비밀번호 재설정 메일 발송 안내에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get passwordResetSent => _isEnglish
      ? 'Password reset instructions were sent by email.'
      : '비밀번호 재설정 메일을 보냈습니다.';
  // 함수이름: servicesUnavailable
  // 함수역할: 로그인 서비스 일시 중단 안내에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get servicesUnavailable => _isEnglish
      ? 'MedBuddy secure services are temporarily unavailable.'
      : '지금은 로그인 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
  // 함수이름: retryStartup
  // 함수역할: 보안 서비스 재연결 버튼에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get retryStartup => _isEnglish ? 'Retry secure startup' : '다시 연결';
  // 함수이름: continueWithPhone
  // 함수역할: 전화번호 인증 진입 버튼에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get continueWithPhone =>
      _isEnglish ? 'Continue with phone' : '전화번호로 계속하기';
  // 함수이름: phoneSignIn
  // 함수역할: 전화번호 로그인 제목에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get phoneSignIn => _isEnglish ? 'Phone sign-in' : '전화번호로 로그인';
  // 함수이름: phoneNumber
  // 함수역할: 국가번호 포함 전화번호 입력 라벨에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get phoneNumber =>
      _isEnglish ? 'International phone number' : '전화번호 (국가번호 포함)';
  // 함수이름: sendCode
  // 함수역할: 문자 인증번호 발송 버튼에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get sendCode => _isEnglish ? 'Send code' : '인증번호 보내기';
  // 함수이름: enterCode
  // 함수역할: 인증번호 입력 요청 제목에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get enterCode =>
      _isEnglish ? 'Enter verification code' : '인증번호를 입력해 주세요';
  // 함수이름: codeSent
  // 함수역할: 문자 인증번호의 수신 번호를 발송 안내에 넣는다.
  // 매개변수: phone (String?): 수신 번호; null이면 일반 전화번호 표현.
  // 반환값: 현재 언어의 문자 발송 안내.
  String codeSent(String? phone) => _isEnglish
      ? 'A code was sent to ${phone ?? 'your phone'}.'
      : '${phone ?? '입력한 전화번호'}로 인증번호를 보냈습니다.';
  // 함수이름: smsCode
  // 함수역할: 문자 인증번호 입력 라벨에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get smsCode => _isEnglish ? 'SMS code' : '문자 인증번호';
  // 함수이름: verify
  // 함수역할: 문자 인증 확정 버튼에 사용할 현재 언어 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get verify => _isEnglish ? 'Verify' : '인증하기';
}

// 클래스명: _AuthenticationScaffold
// 역할: 인증 단계마다 공통 언어 버튼과 본문 배치를 유지한다.
// 주요 책임: 처리 중 버튼을 제한하고 선택적으로 뒤로가기와 브랜드 표시를 제공한다.
// 속성: languageControl (AppLanguageControl): 언어; isBusy (bool): 처리 중; body (Widget): 본문; onBack (VoidCallback?): 복귀; showWordmark (bool): 브랜드 여부.
class _AuthenticationScaffold extends StatelessWidget {
  final AppLanguageControl languageControl;
  final bool isBusy;
  final Widget body;
  final VoidCallback? onBack;
  final bool showWordmark;

  // 함수이름: _AuthenticationScaffold
  // 함수역할: 인증 본문과 언어·뒤로가기·브랜드 표시 구성을 받는다.
  // 매개변수: languageControl (AppLanguageControl): 언어; isBusy (bool): 처리 상태; body (Widget): 본문; onBack (VoidCallback?): 복귀; showWordmark (bool): 브랜드 여부.
  // 반환값: 새 _AuthenticationScaffold.
  const _AuthenticationScaffold({
    required this.languageControl,
    required this.isBusy,
    required this.body,
    this.onBack,
    this.showWordmark = false,
  });

  // Function Name: _selectLanguage
  // Description: Opens language choices and saves only an explicit selection while the initiating context is still mounted.
  // Parameters: context (BuildContext): Sheet and lifecycle location.
  // Returns: Future<void>; cancellation keeps the prior language and persistence errors propagate.
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                          borderRadius: MedBuddyRadii.small,
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

  // 함수이름: build
  // 함수역할: 언어·복귀 버튼을 본문과 분리하고 처리 중 입력을 제한하는 인증 화면을 구성한다.
  // 매개변수: context (BuildContext): 테마·글자 배율 위치.
  // 반환값: 안전 영역을 적용한 Scaffold.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: showWordmark
                ? const EdgeInsets.fromLTRB(8, 32, 8, 0)
                : const EdgeInsets.symmetric(horizontal: 8),
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
                if (showWordmark)
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 24),
                      child: MedBuddyWordmark(),
                    ),
                  )
                else
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

// 클래스명: _SmsCodeView
// 역할: 문자 인증번호 입력 화면.
// 주요 책임: 인증 제어기의 진행·오류 상태와 공통 언어를 문자 입력 상태에 전달한다.
// 속성: control (AuthenticationControl): 인증 처리; languageControl (AppLanguageControl): 표시 언어.
class _SmsCodeView extends StatefulWidget {
  final AuthenticationControl control;
  final AppLanguageControl languageControl;

  // 함수이름: _SmsCodeView
  // 함수역할: 문자 인증 화면에 인증 처리기와 로그인 화면의 언어 제어기를 연결한다.
  // 매개변수: control (AuthenticationControl): 인증 상태·명령; languageControl (AppLanguageControl): 공유 언어.
  // 반환값: 새 _SmsCodeView.
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
// 역할: 문자 인증번호 입력과 확인·취소 화면 상태.
// 주요 책임: 입력값을 인증 제어기로 전달하고 화면 종료 시 입력 자원을 해제한다.
// 속성: _codeController (TextEditingController): 문자 인증번호.
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
            KeepWordsText(
              text.enterCode,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            KeepWordsText(
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
              KeepWordsText(
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

  // 함수이름: _EmailVerificationView
  // 함수역할: 인증 메일 재전송·확인 화면에 인증 상태와 언어 및 로그아웃 후 복귀 동작을 전달한다.
  // 매개변수: control (AuthenticationControl): 인증 상태·명령; languageControl (AppLanguageControl): 공유 언어; onSignedOut (VoidCallback): 로그아웃 성공 후 로그인 폼 복귀.
  // 반환값: 새 _EmailVerificationView.
  const _EmailVerificationView({
    required this.control,
    required this.languageControl,
    required this.onSignedOut,
  });

  // 함수이름: createState
  // 함수역할: 자동 이메일 인증 조회와 수동 확인 상태를 관리할 객체를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _EmailVerificationViewState.
  @override
  State<_EmailVerificationView> createState() => _EmailVerificationViewState();
}

// 클래스명: _EmailVerificationViewState
// 역할: 전경에서 이메일 인증 상태를 재확인한다.
// 주요 책임: 주기 조회·수동 확인이 겹치지 않게 하고 화면 종료 시 감시를 해제한다.
// 속성: _checkingVerification (bool): 수동 확인 중; _verificationTimer (Timer?): 주기 조회.
class _EmailVerificationViewState extends State<_EmailVerificationView>
    with WidgetsBindingObserver {
  bool _checkingVerification = false;
  Timer? _verificationTimer;

  // 함수이름: initState
  // 함수역할: 앱 수명 감시를 등록하고 전경이면 인증 상태 주기 확인을 예약한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleVerificationChecks();
  }

  // 함수이름: dispose
  // 함수역할: 주기 확인 타이머와 앱 수명 감시를 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  @override
  void dispose() {
    _verificationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 함수이름: _scheduleVerificationChecks
  // 함수역할: 기존 타이머를 취소하고 전경 또는 수명 상태 미확인 시에만 5초 간격 확인을 시작한다.
  // 매개변수: 없음.
  // 반환값: 없음. 백그라운드에서는 새 타이머를 만들지 않는다.
  void _scheduleVerificationChecks() {
    _verificationTimer?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _verificationTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_checkAutomatically()),
    );
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 앱 상태 변경마다 기존 확인을 취소하고 복귀 시 주기 확인과 즉시 확인을 시작한다.
  // 매개변수: state (AppLifecycleState): 새 앱 상태.
  // 반환값: 없음.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _verificationTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _scheduleVerificationChecks();
      unawaited(_checkAutomatically());
    }
  }

  // 함수이름: _checkAutomatically
  // 함수역할: 현재 인증 화면에서 미인증 계정만 확인하며 수동 작업 중에는 건너뛴다.
  // 매개변수: 없음.
  // 반환값: 조용한 상태 확인이 끝나면 완료되는 Future<void>.
  Future<void> _checkAutomatically() async {
    if (!mounted ||
        widget.control.isBusy ||
        !widget.control.emailVerificationRequired ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    await widget.control.refreshEmailVerification(showPendingMessage: false);
  }

  // 함수이름: _checkVerification
  // 함수역할: 수동 인증 확인을 한 번만 실행하고 성공·실패 모두 진행 표시를 해제한다.
  // 매개변수: 없음.
  // 반환값: 확인 완료; 제어기 예외는 호출자에게 전파되는 Future<void>.
  Future<void> _checkVerification() async {
    if (widget.control.isBusy || _checkingVerification) return;
    setState(() => _checkingVerification = true);
    try {
      await widget.control.refreshEmailVerification();
    } finally {
      if (mounted) setState(() => _checkingVerification = false);
    }
  }

  // 함수이름: _returnToSignIn
  // 함수역할: 계정을 삭제하지 않고 로그아웃 후 로그인 폼으로 복귀시킨다. StateError이면 현재 인증 안내를 유지한다.
  // 매개변수: 없음.
  // 반환값: 로그아웃 처리 후 완료되는 Future<void>.
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
            KeepWordsText(
              text.verifyEmail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            KeepWordsText(
              text.verificationEmailSent(control.signedInEmail),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            KeepWordsText(
              text.automaticEmailVerification,
              textAlign: TextAlign.center,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: KeepWordsText(
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
                label: KeepWordsText(
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
              child: KeepWordsText(text.resendEmail),
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
