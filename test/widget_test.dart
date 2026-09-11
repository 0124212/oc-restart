import 'package:flutter_test/flutter_test.dart';

import 'package:oc_restart/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const OcRestartApp());

    // Let frames settle (no server = reconnect timer fires, widget stays stable)
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('ak'), findsOneWidget);
  });
}
