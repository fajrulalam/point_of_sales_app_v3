import 'dart:convert';

import 'package:http/http.dart' as http;

class ExternalVoucherClock {
  static Future<DateTime> read(Uri endpoint, String documentName) async {
    final response = await http
        .post(
          endpoint,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'documents': [documentName],
            'mask': {
              'fieldPaths': ['isActive']
            },
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Firestore clock read failed (${response.statusCode})',
        endpoint,
      );
    }

    final result = jsonDecode(response.body);
    final row = result is List && result.length == 1 ? result.single : null;
    final readTime = row is Map ? row['readTime'] : null;
    final instant = readTime is String ? DateTime.tryParse(readTime) : null;
    if (instant == null || !instant.isUtc) {
      throw const FormatException('Firestore did not return a valid readTime');
    }
    return instant;
  }
}
