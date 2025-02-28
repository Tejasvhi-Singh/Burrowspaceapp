// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
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
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAhMO6hptwDK9OqPtfJXapzBL7OTx5FsoE',
    appId: '1:656915868700:web:389105fa2ddfff935fc3d9',
    messagingSenderId: '656915868700',
    projectId: 'burrowspace',
    authDomain: 'burrowspace.firebaseapp.com',
    storageBucket: 'burrowspace.firebasestorage.app',
    measurementId: 'G-582JT8HHWP',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDMN9Gi3HX5ZciwQOUOMyCEJ2i2EX75Qc8',
    appId: '1:656915868700:android:6c1bcfde31e7fd8a5fc3d9',
    messagingSenderId: '656915868700',
    projectId: 'burrowspace',
    storageBucket: 'burrowspace.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDy5S05fDIO6uy2X9wc3TbE3_7gy-JwQw4',
    appId: '1:656915868700:ios:3b584d4f1957a54c5fc3d9',
    messagingSenderId: '656915868700',
    projectId: 'burrowspace',
    storageBucket: 'burrowspace.firebasestorage.app',
    iosBundleId: 'com.example.burrowspace',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDy5S05fDIO6uy2X9wc3TbE3_7gy-JwQw4',
    appId: '1:656915868700:ios:3b584d4f1957a54c5fc3d9',
    messagingSenderId: '656915868700',
    projectId: 'burrowspace',
    storageBucket: 'burrowspace.firebasestorage.app',
    iosBundleId: 'com.example.burrowspace',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAhMO6hptwDK9OqPtfJXapzBL7OTx5FsoE',
    appId: '1:656915868700:web:a10bab37e39ff3f15fc3d9',
    messagingSenderId: '656915868700',
    projectId: 'burrowspace',
    authDomain: 'burrowspace.firebaseapp.com',
    storageBucket: 'burrowspace.firebasestorage.app',
    measurementId: 'G-CYX720PPFE',
  );
}
