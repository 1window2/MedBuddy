import 'package:flutter/material.dart';

import '../controls/authentication_control.dart';
import '../theme/medbuddy_theme.dart';

class AuthenticationUI extends StatefulWidget {
  final AuthenticationControl control;

  const AuthenticationUI({super.key, required this.control});

  @override
  State<AuthenticationUI> createState() => _AuthenticationUIState();
}

class _AuthenticationUIState extends State<AuthenticationUI> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _createAccount = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
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
                      _createAccount ? 'Create a secure account' : 'Sign in',
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
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').trim().contains('@')
                          ? null
                          : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: _createAccount
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
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
                          : 'Use at least six characters.',
                    ),
                    if (control.errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        control.errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
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
                          : Text(_createAccount ? 'Create account' : 'Sign in'),
                    ),
                    if (!_createAccount)
                      TextButton(
                        onPressed: control.isBusy ? null : _sendPasswordReset,
                        child: const Text('Forgot password?'),
                      ),
                    TextButton(
                      onPressed: control.isBusy
                          ? null
                          : () => setState(() {
                              _createAccount = !_createAccount;
                            }),
                      child: Text(
                        _createAccount
                            ? 'Already have an account? Sign in'
                            : 'New to MedBuddy? Create an account',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: control.isBusy
                          ? null
                          : control.signInWithGoogle,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: control.isBusy ? null : _startPhoneSignIn,
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Continue with phone'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: control.isBusy ? null : _continueAsGuest,
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Continue as guest'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue as guest?'),
        content: const Text(
          'Guest access is tied to this temporary account. Sign in with a '
          'permanent account before changing devices or clearing app data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await widget.control.signInAnonymously();
    }
  }
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
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
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
                    onPressed: control.isBusy
                        ? null
                        : control.cancelSmsChallenge,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
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
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
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
          ),
        ),
      ),
    );
  }
}
