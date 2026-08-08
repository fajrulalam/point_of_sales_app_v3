import 'package:integration_test/integration_test.dart';

import '../test/member_program_emulator_test.dart' as emulator_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  emulator_tests.main();
}
