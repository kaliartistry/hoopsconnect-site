import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/board/widgets/post_card.dart';
import 'package:hoops_connect/models/post_model.dart';

void main() {
  Widget buildCard({
    required PostModel post,
    required String currentUserId,
    Future<void> Function()? onAcknowledge,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: PostCard(
          post: post,
          currentUserId: currentUserId,
          onAcknowledge: onAcknowledge,
          onTap: onTap,
        ),
      ),
    );
  }

  testWidgets('only an assigned user is offered acknowledgment', (
    tester,
  ) async {
    var acknowledgeCalls = 0;
    final post = _post(expectedUserId: 'assigned');

    await tester.pumpWidget(
      buildCard(
        post: post,
        currentUserId: 'unassigned',
        onAcknowledge: () async => acknowledgeCalls += 1,
      ),
    );

    expect(find.text('ACK REQUIRED'), findsNothing);
    expect(find.text('Acknowledge'), findsNothing);

    await tester.pumpWidget(
      buildCard(
        post: post,
        currentUserId: 'assigned',
        onAcknowledge: () async => acknowledgeCalls += 1,
      ),
    );
    await tester.pump();

    expect(find.text('ACK REQUIRED'), findsOneWidget);
    expect(find.text('Acknowledge'), findsOneWidget);
    await tester.tap(find.text('Acknowledge'));
    expect(acknowledgeCalls, 1);
  });

  testWidgets('confirmed copy does not claim notification delivery', (
    tester,
  ) async {
    final post = _post(
      expectedUserId: 'assigned',
      ackStatus: {
        'assigned': AckStatusEntry(
          name: 'Assigned Rep',
          teamName: 'Kingston',
          ackedAt: DateTime.utc(2026, 9, 11, 15),
        ),
      },
    );

    await tester.pumpWidget(buildCard(post: post, currentUserId: 'assigned'));

    expect(find.text('ACKNOWLEDGED'), findsOneWidget);
    expect(find.text('Acknowledged'), findsOneWidget);
    expect(find.textContaining('admin notified'), findsNothing);
  });

  testWidgets('card tap uses a keyboard-accessible Material control', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      buildCard(
        post: _post(expectedUserId: 'assigned'),
        currentUserId: 'unassigned',
        onTap: () => taps += 1,
      ),
    );

    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(taps, 1);
  });
}

PostModel _post({
  required String expectedUserId,
  Map<String, AckStatusEntry> ackStatus = const {},
}) {
  return PostModel(
    id: 'post-1',
    authorId: 'admin',
    authorName: 'Association',
    authorRole: 'admin',
    type: PostType.announcement,
    title: 'Schedule update',
    body: 'Please review the updated schedule.',
    visibility: PostVisibility.internal,
    createdAt: DateTime.utc(2026, 9, 11, 14),
    requiresAck: true,
    expectedAcks: {
      expectedUserId: const AckExpectedEntry(
        name: 'Assigned Rep',
        teamName: 'Kingston',
      ),
    },
    ackStatus: ackStatus,
  );
}
