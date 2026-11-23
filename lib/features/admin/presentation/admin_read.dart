import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

const adminReadTimeout = Duration(seconds: 12);

Future<T> boundedAdminRead<T>(
  String operation,
  Future<T> Function() read, {
  Duration timeout = adminReadTimeout,
}) async {
  try {
    return await read().timeout(timeout);
  } catch (error) {
    final code = error is FirebaseException
        ? error.code
        : error is TimeoutException
        ? 'timeout'
        : error.runtimeType.toString();
    developer.log('$operation failed ($code)', name: 'foreseeme.admin');
    rethrow;
  }
}

class AdminReadError extends StatelessWidget {
  final String message;
  final Object error;
  final VoidCallback retry;

  const AdminReadError({
    super.key,
    required this.message,
    required this.error,
    required this.retry,
  });

  @override
  Widget build(BuildContext context) {
    final code = error is FirebaseException
        ? (error as FirebaseException).code
        : null;
    final reason = switch (code) {
      'mfa-required' => 'Sign in with an enrolled second factor.',
      'permission-denied' || 'unauthenticated' =>
        'Check your administrator session and sign in again if needed.',
      'unavailable' ||
      'network-request-failed' => 'Check your connection and try again.',
      'failed-precondition' => 'Check the Firestore configuration and indexes.',
      _ when error is TimeoutException => 'The request timed out. Try again.',
      _ => 'Try again. If the problem persists, contact the service operator.',
    };
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$message $reason', textAlign: TextAlign.center),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
