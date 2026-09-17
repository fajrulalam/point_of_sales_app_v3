import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Services/OrderConfirmationService.dart';

void main() {
  testWidgets('showTopError shows error and dismisses on outside click',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    OrderConfirmationService.showTopError(
                        context, 'Nama member wajib diisi');
                  },
                  child: const Text('Click OK'),
                );
              },
            ),
          ),
        ),
      ),
    );

    // Initial state: no error card visible
    expect(find.text('Nama member wajib diisi'), findsNothing);

    // Click the button to trigger the error
    await tester.tap(find.text('Click OK'));
    await tester.pumpAndSettle();

    // Error card should be visible
    expect(find.text('Nama member wajib diisi'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Tap on the error card text itself - should NOT dismiss
    await tester.tap(find.text('Nama member wajib diisi'));
    await tester.pumpAndSettle();
    expect(find.text('Nama member wajib diisi'), findsOneWidget);

    // Tap anywhere outside the error floating card (e.g. at bottom center)
    await tester.tapAt(const Offset(400, 500));
    await tester.pumpAndSettle();

    // Error card should have disappeared
    expect(find.text('Nama member wajib diisi'), findsNothing);
  });

  testWidgets('showTopError dismisses when clicking close icon',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    OrderConfirmationService.showTopError(
                        context, 'Nama member wajib diisi');
                  },
                  child: const Text('Click OK'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Click OK'));
    await tester.pumpAndSettle();
    expect(find.text('Nama member wajib diisi'), findsOneWidget);

    // Tap close icon
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Nama member wajib diisi'), findsNothing);
  });

  testWidgets('showTopError replaces previous error when triggered repeatedly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    OrderConfirmationService.showTopError(
                        context, 'Nama member wajib diisi');
                  },
                  child: const Text('Trigger 1'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trigger 1'));
    await tester.pumpAndSettle();
    expect(find.text('Nama member wajib diisi'), findsOneWidget);

    final context = tester.element(find.text('Trigger 1'));
    OrderConfirmationService.showTopError(context, 'Pilih program voucher');
    await tester.pumpAndSettle();

    expect(find.text('Nama member wajib diisi'), findsNothing);
    expect(find.text('Pilih program voucher'), findsOneWidget);

    // Cleanup: dismiss error so timer cancels
    OrderConfirmationService.dismissTopError();
    await tester.pumpAndSettle();
  });

  testWidgets('showTopError automatically dismisses after 4 seconds',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    OrderConfirmationService.showTopError(
                        context, 'Nama member wajib diisi');
                  },
                  child: const Text('Click OK'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Click OK'));
    await tester.pump();
    expect(find.text('Nama member wajib diisi'), findsOneWidget);

    // Advance 4 seconds
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Nama member wajib diisi'), findsNothing);
  });
}
