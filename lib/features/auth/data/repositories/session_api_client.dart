import 'package:http/http.dart' as http;

import '../../../../core/network/https_api_url.dart';

class SessionApiClient {
  SessionApiClient(this._client, this._configuredUrl);

  final http.Client _client;
  final String _configuredUrl;

  Future<void> revoke(String token) async {
    final base = httpsApiUrl(_configuredUrl);
    if (base == null) throw StateError('Session service is unavailable');
    final endpoint = base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'v1',
        'session',
        'logout',
      ],
    );
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token';
    final status = await _client
        .send(request)
        .then(http.Response.fromStream)
        .then((response) => response.statusCode)
        .timeout(const Duration(seconds: 12));
    if (status != 204) throw StateError('Session revocation is unconfirmed');
  }
}
