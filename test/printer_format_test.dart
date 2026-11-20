import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Controllers/HomeController.dart';

void main() {
  group('Printer 2-column line formatting tests (58mm 32-character limit)', () {
    test('Receipt item from photo fits on 1 line (32 chars)', () {
      final line = HomeController.format2Column(
        left: '(1) Nasi Putih (bgks)',
        right: '4000',
        maxChars: 32,
      );

      expect(line.length, 32);
      expect(line, '(1) Nasi Putih (bgks)       4000');
    });

    test('Header (QTY) ITEM and SUBTOTAL fits on 1 line (32 chars)', () {
      final line = HomeController.format2Column(
        left: '(QTY) ITEM',
        right: 'SUBTOTAL',
        maxChars: 32,
      );

      expect(line.length, 32);
      expect(line, '(QTY) ITEM              SUBTOTAL');
    });

    test('Date and Queue Number fits on 1 line (32 chars)', () {
      final line = HomeController.format2Column(
        left: '06-11-26 13:46',
        right: 'No. 76',
        maxChars: 32,
      );

      expect(line.length, 32);
      expect(line, '06-11-26 13:46            No. 76');
    });

    test('Long item name is truncated with .. so it never wraps past 32 chars', () {
      final line = HomeController.format2Column(
        left: '(1) Ayam Goreng Kalasan Spesial Sambal Bawang (bgks)',
        right: '35000',
        maxChars: 32,
      );

      expect(line.length, 32);
      expect(line.endsWith('35000'), isTrue);
      expect(line, '(1) Ayam Goreng Kalasan..  35000');
    });

    test('Price and subtotal remain intact even with long name', () {
      final line = HomeController.format2Column(
        left: '(2) Es Teh Manis Jumbo Spesial',
        right: '10000',
        maxChars: 32,
      );

      expect(line.length, 32);
      expect(line.endsWith('10000'), isTrue);
      expect(line, '(2) Es Teh Manis Jumbo S.. 10000');
    });

    test('Short names have proper spacing between left and right', () {
      final line = HomeController.format2Column(
        left: '(1) Teh',
        right: '3000',
        maxChars: 32,
      );

      expect(line.length, 32);
      expect(line, '(1) Teh                     3000');
    });

    test('Handles empty strings safely', () {
      final lineLeftEmpty = HomeController.format2Column(
        left: '',
        right: '4000',
        maxChars: 32,
      );
      expect(lineLeftEmpty.length, 32);

      final lineRightEmpty = HomeController.format2Column(
        left: 'Item',
        right: '',
        maxChars: 32,
      );
      expect(lineRightEmpty.length, 32);
    });
  });
}
