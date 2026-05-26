import 'package:flutter_test/flutter_test.dart';
import 'package:unza_z_chat/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const UnZAzChatApp());
    expect(find.byType(UnZAzChatApp), findsOneWidget);
  });
}
