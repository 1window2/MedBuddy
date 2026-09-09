// File Name: authentication_ui_boundary.dart
// Role: UI boundaries and helpers for sign-in, account creation, and email or SMS verification.
import 'package:flutter/material.dart';

import '../controls/app_language_control.dart';
import '../controls/authentication_control.dart';
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
class _AuthenticationUIState extends State<AuthenticationUI> {
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
    _emailController.dispose();
    _passwordController.dispose();
    _languageControl.removeListener(_handleLanguageChanged);
    if (_ownsLanguageControl) {
      _languageControl.dispose();
    }
    super.dispose();
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
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    errorMessage ??
                        'MedBuddy secure services are temporarily unavailable.',
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
                    label: const Text('Retry secure startup'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (control.configurationFailed) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                errorMessage ?? 'MedBuddy authentication is unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ),
      );
    }
    if (control.emailVerificationRequired) {
      return _EmailVerificationView(control: control);
    }
    if (control.smsCodeRequired &&
        control.smsChallengePurpose != SmsChallengePurpose.mfaEnrollment) {
      return _SmsCodeView(control: control);
    }

    return Scaffold(
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
                            label: const Text('Continue with phone'),
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
            Positioned(
              top: 0,
              right: 8,
              child: Semantics(
                label: text.changeLanguage,
                button: true,
                child: IconButton(
                  key: const Key('authentication-language-toggle'),
                  tooltip: text.changeLanguage,
                  onPressed: _toggleLanguage,
                  icon: const Icon(Icons.language),
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

  // Function Name: _toggleLanguage
  // Description: Requests a Korean/English language toggle from the language controller.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _toggleLanguage() async {
    await _languageControl.toggleLanguage();
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
    final sent = await widget.control.sendPasswordReset(_emailController.text);
    if (!mounted || !sent) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password reset instructions were sent by email.'),
      ),
    );
  }

  // Function Name: _startPhoneSignIn
  // Description: Collects an international phone number and starts SMS verification unless canceled.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _startPhoneSignIn() async {
    final phoneController = TextEditingController(text: '+82');
    final phoneNumber = await showDialog<String>(
      context: context,
      // Function Name: _startPhoneSignIn.builder callback
      // Description: Composes sign-in methods and the account creation form with Text, InputDecoration for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context) => AlertDialog(
        title: const Text('Phone sign-in'),
        content: TextField(
          controller: phoneController,
          autofocus: true,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(
            labelText: 'International phone number',
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            // Function Name: _startPhoneSignIn.onPressed callback
            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, phoneController.text)`.
            // Parameters:
            // - None.
            // Returns: No callback payload; any selection is delivered through the route result.
            onPressed: () => Navigator.pop(context, phoneController.text),
            child: const Text('Send code'),
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
}

// Class Name: _SmsCodeView
// Role: Represents six-digit SMS code entry, verification, and cancellation.
// Responsibilities:
// - Holds the configuration consumed by the State responsible for six-digit SMS code entry, verification, and cancellation.
// Attributes:
// - control (AuthenticationControl): Controller handling this screen's queries and update requests.
class _SmsCodeView extends StatefulWidget {
  final AuthenticationControl control;

  // Function Name: _SmsCodeView
  // Description: Initializes six-digit SMS code entry, verification, and cancellation with the supplied configuration.
  // Parameters:
  // - control (AuthenticationControl): Controller handling this screen's queries and update requests.
  // Returns: Initialized _SmsCodeView instance.
  const _SmsCodeView({required this.control});

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
    return Scaffold(
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
            const Text(
              'Enter verification code',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'A code was sent to '
              '${control.smsDestination ?? 'your phone'}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'SMS code',
                border: OutlineInputBorder(),
              ),
            ),
            if (control.errorMessage != null)
              Text(
                control.errorMessage!,
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
              child: const Text('Verify'),
            ),
            TextButton(
              onPressed: control.isBusy ? null : control.cancelSmsChallenge,
              child: const Text('Cancel'),
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
class _EmailVerificationView extends StatelessWidget {
  final AuthenticationControl control;

  // Function Name: _EmailVerificationView
  // Description: Initializes verification-email resending and email verification status checks with the supplied configuration.
  // Parameters:
  // - control (AuthenticationControl): Controller handling this screen's queries and update requests.
  // Returns: Initialized _EmailVerificationView instance.
  const _EmailVerificationView({required this.control});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 인증 메일 재전송과 이메일 인증 상태 재확인 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 인증 메일 재전송과 이메일 인증 상태 재확인에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            const Text(
              'Verify your email',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'A verification link was sent to '
              '${control.signedInEmail ?? 'your email address'}.',
              textAlign: TextAlign.center,
            ),
            if (control.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                control.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: control.isBusy
                  ? null
                  : control.refreshEmailVerification,
              child: const Text('I verified my email'),
            ),
            TextButton(
              onPressed: control.isBusy
                  ? null
                  : control.resendEmailVerification,
              child: const Text('Resend verification email'),
            ),
            TextButton(
              onPressed: control.isBusy ? null : control.signOut,
              child: const Text('Use another account'),
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
