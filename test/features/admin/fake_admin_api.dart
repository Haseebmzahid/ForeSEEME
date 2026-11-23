import 'package:fyp_foreseeme/features/admin/data/repositories/admin_api_client.dart';
import 'package:http/testing.dart';

class FakeAdminApi extends AdminApiClient {
  FakeAdminApi()
    : super(MockClient((_) => throw StateError('Unexpected HTTP request')));

  final calls = <(List<String>, Map<String, dynamic>?)>[];
  AdminApiException? failure;

  @override
  Future<void> post(List<String> path, [Map<String, dynamic>? payload]) async {
    calls.add((path, payload));
    if (failure case final error?) throw error;
  }
}
