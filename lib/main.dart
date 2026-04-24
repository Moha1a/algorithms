import 'dart:async';
import 'dart:ui';

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
    debugPrint('BACKGROUND HANDLER ERROR: $error');
    debugPrint('$stackTrace');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER ERROR: ${details.exception}');
    debugPrint('${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNHANDLED PLATFORM ERROR: $error');
    debugPrint('$stack');
    return true;
  };

  debugPrint('APP STARTED');
  final firebaseInitFuture = _initializeFirebaseWithLogs();

  runApp(
    MonfathakApp(firebaseInitFuture: firebaseInitFuture),
  );
}

Future<void> _initializeFirebaseWithLogs() async {
  debugPrint('FIREBASE INIT START');
  try {
    await _ensureFirebaseInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('FIREBASE INIT SUCCESS');
  } catch (error, stackTrace) {
    debugPrint('FIREBASE INIT FAILED: $error');
    debugPrint('$stackTrace');
    rethrow;
  }
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
  const MonfathakApp({super.key, required this.firebaseInitFuture});

  final Future<void> firebaseInitFuture;

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
      home: _FirebaseBootstrapper(firebaseInitFuture: firebaseInitFuture),
    );
  }
}

class _FirebaseBootstrapper extends StatefulWidget {
  const _FirebaseBootstrapper({required this.firebaseInitFuture});

  final Future<void> firebaseInitFuture;

  @override
  State<_FirebaseBootstrapper> createState() => _FirebaseBootstrapperState();
}

class _FirebaseBootstrapperState extends State<_FirebaseBootstrapper> {
  late final Future<Widget> _initialScreenFuture;

  @override
  void initState() {
    super.initState();
    _initialScreenFuture = _bootstrapApp();
  }

  Future<Widget> _bootstrapApp() async {
    await widget.firebaseInitFuture;
    Future.microtask(_initPushNonBlocking);
    return _resolveInitialScreen();
  }

  Future<void> _initPushNonBlocking() async {
    try {
      debugPrint('PUSH INIT START');
      await PushNotificationsService.instance.initialize(rootNavigatorKey);
    } catch (error, stackTrace) {
      debugPrint('PUSH INIT FAILED: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<Widget> _resolveInitialScreen() async {
    debugPrint('INITIAL SCREEN RESOLVE START');
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
      debugPrint('INITIAL SCREEN RESOLVE FAILED: $error');
      debugPrint('$stackTrace');
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
        if (profileSnap.hasError) {
          return _StartupErrorScreen(error: profileSnap.error);
        }
        return profileSnap.data ?? const RoleSelectionScreen();
      },
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 64, color: Colors.redAccent),
                const SizedBox(height: 12),
                const Text(
                  'تعذر تشغيل التطبيق',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'حدث خطأ أثناء تهيئة Firebase أو بدء التشغيل. يمكنك المتابعة لشاشة البداية أو إعادة المحاولة.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                if (kDebugMode && error != null)
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                      (_) => false,
                    );
                  },
                  child: const Text('المتابعة إلى شاشة البداية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}