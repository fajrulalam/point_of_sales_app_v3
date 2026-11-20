import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:point_of_sales_app_v3/Services/ExternalVoucherClock.dart';

void main() {
  final endpoint = Uri.https(
    'firestore.googleapis.com',
    '/v1/projects/demo-vouchers/databases/(default)/documents:batchGet',
  );
  const document =
      'projects/demo-vouchers/databases/(default)/documents/vouchers/AB12';

  test('uses the Firestore read time to calculate the reservation deadline',
      () async {
    final serverTime = await http.runWithClient(
      () => ExternalVoucherClock.read(endpoint, document),
      () => MockClient((request) async {
        expect(request.url, endpoint);
        expect(request.method, 'POST');
        expect(jsonDecode(request.body)['documents'], [document]);
        return http.Response(
            '[{"readTime":"2026-11-20T07:00:00.123456Z"}]', 200);
      }),
    );

    expect(serverTime, DateTime.utc(2026, 11, 20, 7, 0, 0, 123, 456));
    expect(serverTime.add(const Duration(minutes: 15)).minute, 15);
  });

  test('fails when Firestore supplies no clock', () async {
    await expectLater(
      http.runWithClient(
        () => ExternalVoucherClock.read(endpoint, document),
        () => MockClient((_) async => http.Response('[{}]', 200)),
      ),
      throwsFormatException,
    );
  });
}
