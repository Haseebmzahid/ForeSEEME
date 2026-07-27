import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/admin/presentation/admin_user_detail_screen.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';

void main() {
  testWidgets('renders every field read-only plus the operator-only note', (
    tester,
  ) async {
    final entry = UserDirectoryEntry(
      uid: 'u1',
      name: 'Alice Khan',
      email: 'alice@example.com',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      status: UserStatus.active,
    );

    await tester.pumpWidget(
      MaterialApp(home: AdminUserDetailScreen(entry: entry)),
    );

    expect(find.text('Alice Khan'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('u1'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(find.textContaining('operator script'), findsOneWidget);
  });

  testWidgets('a missing name renders an em dash, not a crash', (tester) async {
    final entry = UserDirectoryEntry(
      uid: 'u2',
      name: null,
      email: 'bob@example.com',
      createdAt: DateTime.now().toUtc(),
      status: UserStatus.pending,
    );

    await tester.pumpWidget(
      MaterialApp(home: AdminUserDetailScreen(entry: entry)),
    );

    expect(find.text('—'), findsOneWidget);
  });
}
