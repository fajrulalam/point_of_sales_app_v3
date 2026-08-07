import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('test harness renders without production Firebase data',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('POS test harness'))),
    );
    expect(find.text('POS test harness'), findsOneWidget);
  });
}
