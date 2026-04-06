import 'package:flutter_test/flutter_test.dart';
import 'package:innovative_cuppa/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const InnovativeCuppaApp());

    // Verify that our app shows the welcome message.
    expect(find.text('Admin Dashboard'), findsOneWidget);
  });
}
