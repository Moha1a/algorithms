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
    apiKey: 'AIzaSyAt8R2iub5RaBG2vYnCT56zZGfcslEQ7U4',
    appId: '1:1025525101614:web:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    authDomain: 'qiqa-c17c2.firebaseapp.com',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyALEGcShx9HYqSJ6wE1KoUKk5JIEOwWyKw',
    appId: '1:1025525101614:android:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAt8R2iub5RaBG2vYnCT56zZGfcslEQ7U4',
    appId: '1:1025525101614:ios:cd97beff914ba68dcfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    storageBucket: 'qiqa-c17c2.appspot.com',
    iosBundleId: 'com.company.manfathak',
    iosClientId: '1025525101614-fko0al4vba9iumthi76rotmqvfmtnq0e.apps.googleusercontent.com',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAt8R2iub5RaBG2vYnCT56zZGfcslEQ7U4',
    appId: '1:1025525101614:ios:cd97beff914ba68dcfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    storageBucket: 'qiqa-c17c2.appspot.com',
    iosBundleId: 'com.company.manfathak',
    iosClientId: '1025525101614-fko0al4vba9iumthi76rotmqvfmtnq0e.apps.googleusercontent.com',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAt8R2iub5RaBG2vYnCT56zZGfcslEQ7U4',
    appId: '1:1025525101614:web:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    authDomain: 'qiqa-c17c2.firebaseapp.com',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyAt8R2iub5RaBG2vYnCT56zZGfcslEQ7U4',
    appId: '1:1025525101614:web:08c4c874f05d1713cfdbbf',
    messagingSenderId: '1025525101614',
    projectId: 'qiqa-c17c2',
    authDomain: 'qiqa-c17c2.firebaseapp.com',
    storageBucket: 'qiqa-c17c2.appspot.com',
  );
}