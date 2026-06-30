import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/home/screens/home/components/home_app_bar_actions.dart';

void main() {
  Future<void> pumpActions(WidgetTester tester, int unreadCount, {int reminderCount = 0}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeAppBarActions(
            unreadCount: unreadCount,
            reminderCount: reminderCount,
            onPurchaseHistory: () {},
            onNotifications: () {},
            onAccount: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('hides the badge when there are no unread notifications', (tester) async {
    await pumpActions(tester, 0);

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    // No numeric badge text is rendered at zero.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('shows the unread count on the badge', (tester) async {
    await pumpActions(tester, 3);

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('caps the badge at 9+', (tester) async {
    await pumpActions(tester, 12);

    expect(find.text('9+'), findsOneWidget);
    expect(find.text('12'), findsNothing);
  });

  testWidgets('badges aging reminders even with zero unread notifications', (tester) async {
    await pumpActions(tester, 0, reminderCount: 2);

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('badge combines unread notifications and reminders', (tester) async {
    await pumpActions(tester, 1, reminderCount: 2);

    expect(find.text('3'), findsOneWidget);
  });
}
