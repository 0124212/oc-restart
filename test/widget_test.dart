import 'package:flutter_test/flutter_test.dart';

import 'package:oc_restart/main.dart';

void main() {
  testWidgets('Restart button renders', (WidgetTester tester) async {
    await tester.pumpWidget(const OcRestartApp());

    expect(find.text('Restart OpenCode'), findsOneWidget);
    expect(find.textContaining('Services up:'), findsOneWidget);
  });
}
