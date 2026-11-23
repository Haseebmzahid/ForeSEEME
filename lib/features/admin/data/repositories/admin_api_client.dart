import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:fyp_foreseeme/core/network/https_api_url.dart';

final adminApiClientProvider = Provider<AdminApiClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AdminApiClient(client);
});

class AdminApiException implements Exception {
  final String code;
  final String? requestId;

  const AdminApiException(this.code, {this.requestId});

  @override
  String toString() {
    final message = switch (code) {
      'not_configured' => 'The administrative service is not configured.',
      'recent_sign_in_required' ||
      'invalid_session' ||
      'mfa_required' => 'Sign out and sign in again with your second factor.',
      'admin_required' => 'An administrator session is required.',
      'account_operation_pending' =>
        'This account has a pending operation. Contact the service operator.',
      'protected_account' => 'This administrator account is protected.',
      'invitation_unavailable' => 'Invitation email is not configured.',
      'invitation_pending' =>
        'An invitation is already in progress for this email.',
      'invitation_delivery_unconfirmed' =>
        'The account was created. Email could not be confirmed. Submit the same address to retry delivery.',
      'invitation_restart_required' =>
        'The original account no longer exists. Submit again to start a new invitation.',
      'account_exists' => 'An account already exists for this email.',
      'article_exists' =>
        'An article already uses this link. Choose a different title.',
      'article_missing' =>
        'This article no longer exists. Refresh the article list.',
      'no_active_override' => 'There is no active override to clear.',
      'rate_limited' => 'Too many changes. Wait a minute and try again.',
      'invalid_input' ||
      'invalid_expiry' => 'Review the fields and submit again.',
      'operation_unconfirmed' || 'timeout' =>
        'The outcome could not be confirmed. Refresh before retrying.',
      _ => 'The administrative action could not be completed.',
    };
    return requestId == null ? message : '$message Reference $requestId.';
  }
}

class AdminApiClient {
  final http.Client _client;
  AdminApiClient(this._client);

  Future<void> post(List<String> path, [Map<String, dynamic>? payload]) async {
    const configured = String.fromEnvironment('ADMIN_API_URL');
    final base = httpsApiUrl(configured);
    if (base == null) {
      throw const AdminApiException('not_configured');
    }

    try {
      final token = await FirebaseAuth.instance.currentUser
          ?.getIdToken()
          .timeout(const Duration(seconds: 8));
      if (token == null) throw const AdminApiException('invalid_session');
      final endpoint = base.replace(
        pathSegments: [
          ...base.pathSegments.where((segment) => segment.isNotEmpty),
          'v1',
          ...path,
        ],
      );
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer $token';
      if (payload != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(payload);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode >= 200 && response.statusCode < 300) return;
      final decoded = jsonDecode(response.body);
      final detail = decoded is Map ? decoded['detail'] : null;
      final code = detail is Map ? detail['code'] : null;
      final requestId = detail is Map ? detail['requestId'] : null;
      throw AdminApiException(
        code is String ? code : 'unavailable',
        requestId:
            requestId is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId)
            ? requestId
            : null,
      );
    } on TimeoutException {
      throw const AdminApiException('timeout');
    } on AdminApiException {
      rethrow;
    } catch (_) {
      throw const AdminApiException('unavailable');
    }
  }
}
