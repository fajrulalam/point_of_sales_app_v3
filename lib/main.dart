import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:point_of_sales_app_v3/Screens/Home.dart';
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData.light().copyWith(
          colorScheme:
              ThemeData().colorScheme.copyWith(primary: Colors.black87),
          appBarTheme: AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 1,
              titleTextStyle: TextStyle(
                  color: Colors.black45,
                  fontWeight: FontWeight.w500,
                  fontSize: 18))),
      initialRoute: Home.id,
      locale: Locale('id'),
      routes: {
        Home.id: (context) => Home(),
      },
    );
  }
}
