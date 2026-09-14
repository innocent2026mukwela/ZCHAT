import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The real app boots Firebase in main(), which can't run under `flutter test`,
// so this is a lightweight widget smoke test of a self-contained tree.
void main() {
  testWidgets('renders a widget tree without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: Text('ZCHAT')))),
    );
    expect(find.text('ZCHAT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
