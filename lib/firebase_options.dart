import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
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

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I',
    appId: '1:1025525101614:web:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    authDomain: 'qiqa-c17c2.firebaseapp.com',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );
}