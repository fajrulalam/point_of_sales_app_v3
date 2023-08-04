// File generated by FlutterFire CLI.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCZ1oJuagSPQ_9VWiFONeArwxtUsgLGhCA',
    appId: '1:932379156472:android:013cd61d44258e9155c00d',
    messagingSenderId: '932379156472',
    projectId: 'point-of-sales-app-25e2b',
    databaseURL: 'https://point-of-sales-app-25e2b-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'point-of-sales-app-25e2b.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB192AovFGEvgtMsH-BahJvokpFeUZM5JQ',
    appId: '1:932379156472:ios:9c3333fe6ec5b3a255c00d',
    messagingSenderId: '932379156472',
    projectId: 'point-of-sales-app-25e2b',
    databaseURL: 'https://point-of-sales-app-25e2b-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'point-of-sales-app-25e2b.appspot.com',
    iosClientId: '932379156472-f5c96lnckhk29b2pj0qi4mtfk97h7k8d.apps.googleusercontent.com',
    iosBundleId: 'com.example.pointOfSalesAppV3',
  );
}