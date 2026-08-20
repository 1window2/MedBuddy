import 'package:flutter/material.dart';

import '../controls/app_language_control.dart';
import '../controls/authentication_control.dart';
import '../theme/medbuddy_theme.dart';

class AuthenticationUI extends StatefulWidget {
  final AuthenticationControl control;
  final AppLanguageControl? languageControl;

  const AuthenticationUI({
    super.key,
    required this.control,
    this.languageControl,
  });

  @override
  State<AuthenticationUI> createState() => _AuthenticationUIState();
}

class _AuthenticationUIState extends State<AuthenticationUI> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _createAccount = false;
  bool _obscurePassword = true;
  late final AppLanguageControl _languageControl;
  late final bool _ownsLanguageControl;

  @override
  void initState() {
    super.initState();
    _ownsLanguageControl = widget.languageControl == null;
    _languageControl =
        widget.languageControl ?? AppLanguageControl(loadPersisted: false);
    _languageControl.addListener(_handleLanguageChanged);
  }

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

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final text = _AuthenticationText(_languageControl.language);
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
                    control.errorMessage ??
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
                control.errorMessage ??
                    'MedBuddy authentication is unavailable.',
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
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => (value ?? '').length >= 6
                              ? null
                              : text.invalidPassword,
                        ),
                        if (control.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            control.errorMessage!,
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

  // Rebuilds this boundary whenever the device-wide language changes.
  void _handleLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleLanguage() async {
    await _languageControl.toggleLanguage();
  }

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

  Future<void> _startPhoneSignIn() async {
    final phoneController = TextEditingController(text: '+82');
    final phoneNumber = await showDialog<String>(
      context: context,
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
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

  Future<void> _continueAsGuest() async {
    final text = _AuthenticationText(_languageControl.language);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.guestConfirmationTitle),
        content: Text(text.guestConfirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.cancel),
          ),
          FilledButton(
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

// Class Name: _AuthenticationText
// Role: Supplies the authentication screen's Korean and English labels.
// Responsibilities:
// - Keep the sign-in boundary usable in the device-wide selected language.
// - Preserve concise validation, guest-consent, and progress messages.
class _AuthenticationText {
  final String language;

  const _AuthenticationText(this.language);

  bool get _isEnglish => language == 'en';

  String get signIn => _isEnglish ? 'Sign in' : '로그인';
  String get createAccountTitle =>
      _isEnglish ? 'Create a secure account' : '안전한 계정 만들기';
  String get email => _isEnglish ? 'Email' : '이메일';
  String get password => _isEnglish ? 'Password' : '비밀번호';
  String get showPassword => _isEnglish ? 'Show password' : '비밀번호 표시';
  String get hidePassword => _isEnglish ? 'Hide password' : '비밀번호 숨기기';
  String get invalidEmail =>
      _isEnglish ? 'Enter a valid email address.' : '올바른 이메일 주소를 입력해 주세요.';
  String get invalidPassword =>
      _isEnglish ? 'Use at least six characters.' : '비밀번호는 6자 이상 입력해 주세요.';
  String get retrySecureSession =>
      _isEnglish ? 'Retry secure session' : '보안 세션 다시 연결';
  String get createAccount => _isEnglish ? 'Create account' : '회원가입';
  String get forgotPassword => _isEnglish ? 'Forgot password?' : '비밀번호 찾기';
  String get alreadyHaveAccount =>
      _isEnglish ? 'Already have an account? Sign in' : '이미 계정이 있으신가요? 로그인';
  String get newToMedBuddy => _isEnglish
      ? 'New to MedBuddy? Create an account'
      : 'MedBuddy가 처음이신가요? 회원가입';
  String get or => _isEnglish ? 'or' : '또는';
  String get continueWithGoogle =>
      _isEnglish ? 'Continue with Google' : 'Google로 계속하기';
  String get continueAsGuest =>
      _isEnglish ? 'Continue as guest' : '회원가입 없이 계속하기';
  String get changeLanguage => _isEnglish ? 'Change language' : '언어 변경';
  String get processing => _isEnglish ? 'Please wait…' : '처리 중입니다…';
  String get guestConfirmationTitle =>
      _isEnglish ? 'Continue as guest?' : '게스트로 계속할까요?';
  String get guestConfirmationMessage => _isEnglish
      ? 'Guest access is tied to this temporary account. Sign in with a '
            'permanent account before changing devices or clearing app data.'
      : '게스트 데이터는 이 임시 계정에만 연결됩니다. 기기를 변경하거나 '
            '앱 데이터를 지우기 전에 정식 계정으로 로그인해 주세요.';
  String get cancel => _isEnglish ? 'Cancel' : '취소';
  String get continueLabel => _isEnglish ? 'Continue' : '계속';
}

class _SmsCodeView extends StatefulWidget {
  final AuthenticationControl control;

  const _SmsCodeView({required this.control});

  @override
  State<_SmsCodeView> createState() => _SmsCodeViewState();
}

class _SmsCodeViewState extends State<_SmsCodeView> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

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

class _EmailVerificationView extends StatelessWidget {
  final AuthenticationControl control;

  const _EmailVerificationView({required this.control});

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
// 역할: 키보드와 큰 글씨가 차지하는 공간이 커져도 인증 명령에 접근할 수 있게 한다.
// 주요 책임:
// - 인증 내용을 읽기 좋은 최대 너비로 제한한다.
// - 남은 화면 높이를 채우되 공간이 부족하면 세로 스크롤을 제공한다.
class _ScrollableAuthenticationBody extends StatelessWidget {
  final Widget child;

  const _ScrollableAuthenticationBody({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
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
