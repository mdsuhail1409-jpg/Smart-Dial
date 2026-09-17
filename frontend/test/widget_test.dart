// Placeholder widget test for SmartDial.
// Full UI tests will be added in a later sprint.

import 'package:flutter_test/flutter_test.dart';
import 'package:smartdial/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartDialApp());
    // SplashScreen should be visible initially
    expect(find.text('SmartDial'), findsWidgets);
  });
}
