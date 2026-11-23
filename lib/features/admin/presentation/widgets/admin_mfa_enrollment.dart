import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdminMfaEnrollment extends StatefulWidget {
  const AdminMfaEnrollment({super.key});

  @override
  State<AdminMfaEnrollment> createState() => _AdminMfaEnrollmentState();
}

class _AdminMfaEnrollmentState extends State<AdminMfaEnrollment> {
  TotpSecret? _secret;
  User? _user;
  String _code = '';
  String? _feedback;
  bool _busy = false;
  bool _complete = false;
  bool _emailUnverified = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _feedback = switch (error.code) {
            'requires-recent-login' =>
              'Sign out and sign in again before enrolling.',
            'unverified-email' => 'Verify your email address before enrolling.',
            'invalid-verification-code' => 'The code is incorrect. Try again.',
            _ =>
              'Enrollment failed. Check Identity Platform settings or contact the operator.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback = 'Enrollment could not be completed on this device.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user
        ?.getIdTokenResult(true)
        .timeout(const Duration(seconds: 12));
    if (user == null || token?.claims?['admin'] != true) {
      throw StateError('Administrator account required');
    }
    if (!user.emailVerified) {
      if (mounted) {
        setState(() {
          _user = user;
          _emailUnverified = true;
          _feedback = 'Verify your email before enrolling an authenticator.';
        });
      }
      return;
    }
    final session = await user.multiFactor.getSession().timeout(
      const Duration(seconds: 12),
    );
    final secret = await TotpMultiFactorGenerator.generateSecret(
      session,
    ).timeout(const Duration(seconds: 12));
    if (!mounted) return;
    setState(() {
      _user = user;
      _emailUnverified = false;
      _secret = secret;
    });
  }

  Future<void> _enroll() async {
    final user = _user!;
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('Account changed');
    }
    final assertion = await TotpMultiFactorGenerator.getAssertionForEnrollment(
      _secret!,
      _code,
    );
    await user.multiFactor.enroll(
      assertion,
      displayName: 'ForeSeeMe authenticator',
    );
    if (!mounted) return;
    setState(() {
      _secret = null;
      _code = '';
      _complete = true;
      _feedback =
          'Authenticator enrolled. Sign out and sign in with a fresh code.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final secret = _secret;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Set up administrator MFA'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_complete && secret == null)
                const Text(
                  'Use a verified email and a recent sign-in. Have your authenticator app ready.',
                ),
              if (secret != null) ...[
                const Text(
                  'Enter this setup key into your authenticator app as a time-based account. Keep the key private.',
                ),
                SelectableText(secret.secretKey),
                TextField(
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Authenticator code',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  onChanged: (value) => setState(() => _code = value),
                ),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_feedback != null) Text(_feedback!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(_complete ? 'Done' : 'Cancel'),
          ),
          if (_emailUnverified)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final user = _user!;
                      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
                        throw StateError('Account changed');
                      }
                      await user.sendEmailVerification().timeout(
                        const Duration(seconds: 12),
                      );
                      if (mounted) {
                        setState(
                          () => _feedback =
                              'Verification email sent. Open the link, then sign out and sign in again.',
                        );
                      }
                    }),
              child: const Text('Send verification email'),
            ),
          if (!_complete && !_emailUnverified)
            FilledButton(
              onPressed: _busy || (secret != null && _code.length != 6)
                  ? null
                  : () => _run(secret == null ? _start : _enroll),
              child: Text(secret == null ? 'Generate setup key' : 'Enroll'),
            ),
        ],
      ),
    );
  }
}
