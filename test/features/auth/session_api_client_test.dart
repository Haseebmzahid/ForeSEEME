import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/auth/data/repositories/session_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final url in [
    '',
    'http://api.example.test',
    'https://user@api.example.test',
  ]) {
    test('rejects invalid session service URL: $url', () async {
      final client = MockClient(
        (_) async => throw TestFailure('Unexpected request'),
      );
      await expectLater(
        SessionApiClient(client, url).revoke('credential'),
        throwsStateError,
      );
    });
  }

  test(
    'POSTs a bearer token over HTTPS and rejects redirect responses',
    () async {
      var status = 204;
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.example.test/base/v1/session/logout',
        );
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer credential');
        expect(request.followRedirects, isFalse);
        expect(request.body, isEmpty);
        return http.Response(
          '',
          status,
          headers: {'location': 'http://api.example.test'},
        );
      });
      final service = SessionApiClient(client, 'https://api.example.test/base');
      await service.revoke('credential');
      status = 307;
      await expectLater(service.revoke('credential'), throwsStateError);
    },
  );
}
