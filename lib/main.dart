import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:point_of_sales_app_v3/Screens/Home.dart';
import 'package:point_of_sales_app_v3/Screens/LoginScreen.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'firebase_options.dart';

// ── Bitepoint palette ──────────────────────────────────────────────
const Color _kDarkTeal = Color(0xFF069494);
const Color _kWarmYellow = Color(0xFFF5C518);
const Color _kOffWhite = Color(0xFFF5F5F0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use fonts from pubspec (assets/fonts); avoids runtime HTTP to fonts.gstatic.com when offline.
  GoogleFonts.config.allowRuntimeFetching = false;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Firebase.initializeApp(
    name: 'e-santren',
    options: DefaultFirebaseOptions.eSantrenWeb,
  );

  // Initialize Indonesian locale for date formatting
  await initializeDateFormatting('id_ID', null);

  // Load persisted testing mode preference
  await Col.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if user is already logged in AND not anonymous
    final User? user = FirebaseAuth.instance.currentUser;
    final bool isRealUser = user != null && !user.isAnonymous;

    return ValueListenableBuilder<bool>(
      valueListenable: Col.testingMode,
      builder: (context, isTesting, _) {
        final Color primary = isTesting ? const Color(0xFFE65100) : _kDarkTeal;
        final Color secondary = isTesting ? const Color(0xFFFFAB00) : _kWarmYellow;
        final Color surface = isTesting ? const Color(0xFFFFF3E0) : _kOffWhite;

        return MaterialApp(
          title: isTesting ? '[TESTING] 375 POS' : '375 POS System',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light().copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: primary,
              primary: primary,
              secondary: secondary,
              surface: surface,
            ),
            scaffoldBackgroundColor: surface,
            textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Montserrat'),
            appBarTheme: AppBarTheme(
              backgroundColor: primary,
              elevation: 0,
              titleTextStyle: const TextStyle(
                fontFamily: 'Montserrat',
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            cardTheme: CardThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              elevation: 2,
              color: Colors.white,
            ),
          ),
          // If user is null or anonymous, show login
          initialRoute: isRealUser ? Home.id : LoginScreen.id,
          locale: const Locale('id'),
          routes: {
            Home.id: (context) => const Home(),
            LoginScreen.id: (context) => const LoginScreen(),
          },
        );
      },
    );
  }
}

