import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/auth/data/repositories/session_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('registration and removal send a bearer and no UID', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.headers['authorization'], 'Bearer credential');
      expect(request.followRedirects, isFalse);
      final json = jsonDecode(request.body);
      expect(
        json,
        request.url.path.endsWith('/register')
            ? {'token': 'fixture-current', 'previousToken': 'fixture-previous'}
            : {'token': 'fixture-current'},
      );
      return http.Response('', 204);
    });
    final service = SessionApiClient(client, 'https://api.example.test/base');
    await service.registerNotification(
      'credential',
      'fixture-current',
      previousToken: 'fixture-previous',
    );
    await service.unregisterNotification('credential', 'fixture-current');
    expect(paths, [
      '/base/v1/notifications/register',
      '/base/v1/notifications/unregister',
    ]);
  });

  for (final url in [
    '',
    'http://api.example.test',
    'https://user@api.example.test',
    'https://[::1',
    'https://api.example.test:65536',
    'https://api.example.test:0',
    'https://api.example.test?origin=other',
    'https://api.example.test#fragment',
    'https://api.example.test\\elsewhere',
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

  for (final lostReply in [true, false]) {
    test('retries an unconfirmed logout once, lost reply=$lostReply', () async {
      var requests = 0;
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer fixture');
        expect(request.followRedirects, isFalse);
        if (++requests == 1) {
          if (lostReply) throw http.ClientException('connection interrupted');
          return http.Response('', 503);
        }
        return http.Response('', 204);
      });
      await SessionApiClient(
        client,
        'https://api.example.test',
      ).revoke('fixture');
      expect(requests, 2);
    });
  }

  test(
    'reports an offline logout as unconfirmed after the bounded retry',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        throw http.ClientException('offline');
      });
      final service = SessionApiClient(client, 'https://api.example.test');
      await expectLater(
        service.revoke('fixture'),
        throwsA(isA<http.ClientException>()),
      );
      expect(requests, 2);
    },
  );

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
