import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/second_factor_challenge.dart';

class SecondFactorDialog extends StatefulWidget {
  final List<SecondFactorChoice> choices;
  final Future<void> Function(VerifySecondFactor, String) complete;

  const SecondFactorDialog({
    super.key,
    required this.choices,
    required this.complete,
  });

  @override
  State<SecondFactorDialog> createState() => _SecondFactorDialogState();
}

class _SecondFactorDialogState extends State<SecondFactorDialog> {
  VerifySecondFactor? _verify;
  String _code = '';
  String? _error;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'invalid-verification-code'
              ? 'The code is incorrect. Try again.'
              : 'Verification could not complete. Try again or start a new sign-in.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Verification could not complete. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Verify your sign-in'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_verify == null)
                for (final choice in widget.choices)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final verifier = await choice.prepare();
                            if (mounted) setState(() => _verify = verifier);
                          }),
                    child: Text(choice.label),
                  )
              else
                TextField(
                  autofocus: true,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                  ),
                  onChanged: (text) => setState(() => _code = text),
                ),
              if (_error != null) Text(_error!),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (_verify != null)
            FilledButton(
              onPressed: _busy || _code.length != 6
                  ? null
                  : () => _run(() async {
                      final navigator = Navigator.of(context);
                      await widget.complete(_verify!, _code);
                      if (context.mounted &&
                          ModalRoute.of(context)?.isCurrent == true) {
                        navigator.pop();
                      }
                    }),
              child: const Text('Verify'),
            ),
        ],
      ),
    );
  }
}
