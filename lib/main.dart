import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:point_of_sales_app_v3/Screens/Home.dart';
import 'package:point_of_sales_app_v3/Screens/LoginScreen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Firebase.initializeApp(
    name: 'e-santren',
    options: DefaultFirebaseOptions.eSantrenWeb,
  );

  // Initialize Indonesian locale for date formatting
  await initializeDateFormatting('id_ID', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if user is already logged in AND not anonymous
    final User? user = FirebaseAuth.instance.currentUser;
    final bool isRealUser = user != null && !user.isAnonymous;

    return MaterialApp(
      title: '375 POS System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
          colorScheme:
              ThemeData().colorScheme.copyWith(primary: Colors.black87),
          appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 1,
              titleTextStyle: TextStyle(
                  color: Colors.black45,
                  fontWeight: FontWeight.w500,
                  fontSize: 18))),
      // If user is null or anonymous, show login
      initialRoute: isRealUser ? Home.id : LoginScreen.id,
      locale: const Locale('id'),
      routes: {
        Home.id: (context) => const Home(),
        LoginScreen.id: (context) => const LoginScreen(),
      },
    );
  }
}
