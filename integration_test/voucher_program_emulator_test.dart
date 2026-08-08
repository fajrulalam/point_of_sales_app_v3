import 'package:integration_test/integration_test.dart';

import '../test/voucher_program_emulator_test.dart' as emulator_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  emulator_tests.main();
}
