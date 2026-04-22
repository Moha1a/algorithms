import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/home_shell_screen.dart';
import 'screens/role_selection_screen.dart';
import 'services/push_notifications_service.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
Future<void>? _firebaseInitFuture;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await _ensureFirebaseInitialized();
    await PushNotificationsService.showBackgroundNotification(message);
  } catch (error, stackTrace) {
    print('BACKGROUND HANDLER ERROR: $error');
    print(stackTrace);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('FLUTTER ERROR: ${details.exception}');
    print(details.stack);
  };

  print('APP STARTED');
  await _ensureFirebaseInitialized();
  print('FIREBASE INITIALIZED');
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const MonfathakApp());
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  _firebaseInitFuture ??= kIsWeb
      ? Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        )
      : Firebase.initializeApp();
  await _firebaseInitFuture;
}

class MonfathakApp extends StatelessWidget {
  const MonfathakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'منفذك',
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: AppTheme.light,
      home: const _FirebaseBootstrapper(),
    );
  }
}

class _FirebaseBootstrapper extends StatefulWidget {
  const _FirebaseBootstrapper();

  @override
  State<_FirebaseBootstrapper> createState() => _FirebaseBootstrapperState();
}

class _FirebaseBootstrapperState extends State<_FirebaseBootstrapper> {
  late final Future<Widget> _initialScreenFuture;

  @override
  void initState() {
    super.initState();
    _initialScreenFuture = _resolveInitialScreen();
    Future.microtask(_initPushNonBlocking);
  }

  Future<void> _initPushNonBlocking() async {
    try {
      print('PUSH INIT START');
      await PushNotificationsService.instance.initialize(rootNavigatorKey);
      print('PUSH INIT DONE');
    } catch (error, stackTrace) {
      print('PUSH INIT ERROR: $error');
      print(stackTrace);
      Future.delayed(const Duration(seconds: 3), () async {
        try {
          await PushNotificationsService.instance.initialize(rootNavigatorKey);
        } catch (_) {}
      });
    }
  }

  Future<Widget> _resolveInitialScreen() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return const RoleSelectionScreen();

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final profile = snap.data();
      if (profile == null) return const RoleSelectionScreen();
      return HomeShellScreen(profile: profile);
    } catch (error, stackTrace) {
      print('INITIAL PROFILE LOAD ERROR: $error');
      print(stackTrace);
      return const RoleSelectionScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _initialScreenFuture,
      builder: (context, profileSnap) {
        if (profileSnap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return profileSnap.data ?? const RoleSelectionScreen();
      },
    );
  }
}
