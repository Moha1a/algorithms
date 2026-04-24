import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
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
        return linux;
      case TargetPlatform.fuchsia:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I',
    appId: '1:1025525101614:web:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    authDomain: 'qiqa-c17c2.firebaseapp.com',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I',
    appId: '1:1025525101614:android:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I',
    appId: '1:1025525101614:ios:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    storageBucket: 'qiqa-c17c2.appspot.com',
    iosBundleId: 'com.example.algorithms',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I',
    appId: '1:1025525101614:ios:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    storageBucket: 'qiqa-c17c2.appspot.com',
    iosBundleId: 'com.example.algorithms',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I',
    appId: '1:1025525101614:web:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    authDomain: 'qiqa-c17c2.firebaseapp.com',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I',
    appId: '1:1025525101614:web:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    authDomain: 'qiqa-c17c2.firebaseapp.com',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );
}