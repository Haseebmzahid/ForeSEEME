import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/https_api_url.dart';

class SessionApiClient {
  SessionApiClient(this._client, this._configuredUrl);

  final http.Client _client;
  final String _configuredUrl;

  Future<void> revoke(String token) async {
    const path = ['session', 'logout'];
    const timeout = Duration(seconds: 6);
    try {
      final status = await _send(token, path, timeout: timeout);
      if (status == 204) return;
      if (status != 503) throw StateError('Session operation is unconfirmed');
    } on TimeoutException {
      // The response may have been lost after the server committed logout.
    } on http.ClientException {
      // Retry with the same in-memory bearer before clearing local Auth.
    }
    if (await _send(token, path, timeout: timeout) != 204) {
      throw StateError('Session operation is unconfirmed');
    }
  }

  Future<void> registerNotification(
    String bearer,
    String token, {
    String? previousToken,
  }) => _post(
    bearer,
    ['notifications', 'register'],
    {'token': token, 'previousToken': ?previousToken},
  );

  Future<void> unregisterNotification(String bearer, String token) =>
      _post(bearer, ['notifications', 'unregister'], {'token': token});

  Future<void> _post(
    String bearer,
    List<String> path, [
    Map<String, String>? body,
  ]) async {
    final status = await _send(
      bearer,
      path,
      body: body,
      timeout: const Duration(seconds: 12),
    );
    if (status != 204) throw StateError('Session operation is unconfirmed');
  }

  Future<int> _send(
    String bearer,
    List<String> path, {
    Map<String, String>? body,
    required Duration timeout,
  }) async {
    final base = httpsApiUrl(_configuredUrl);
    if (base == null) throw StateError('Session service is unavailable');
    final endpoint = base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'v1',
        ...path,
      ],
    );
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $bearer';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .then((response) => response.statusCode)
        .timeout(timeout);
  }
}
