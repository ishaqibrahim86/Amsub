// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/app_wrapper.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/lock_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'providers/user_balance_provider.dart';
import 'screens/onboarding_screen.dart';
import 'screens/notifications_screen.dart';   // ← needed for NotificationStore

// ==================== BACKGROUND HANDLER ====================
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _showBackgroundNotification(message);
}

Future<void> _showBackgroundNotification(RemoteMessage message) async {
  final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotifications.initialize(const InitializationSettings(android: androidSettings));

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'amsubnig_channel',
    'Amsubnig Notifications',
    description: 'Wallet funding and transaction alerts',
    importance: Importance.high,
  );

  await localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  final notification = message.notification;
  if (notification == null) return;

  await localNotifications.show(
    notification.hashCode,
    notification.title,
    notification.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );

  // Save to in-app history (works even when app is closed)
  final String msg = notification.body ?? notification.title ?? 'New notification';
  await NotificationStore.addNotification(msg);
}
// ===========================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLoading = true;
  Widget? _initialScreen;

  @override
  void initState() {
    super.initState();
    _checkAuthAndOnboarding();
  }

  Future<void> _checkAuthAndOnboarding() async {
    print('Starting auth & onboarding check...');
    final prefs = await SharedPreferences.getInstance();
    final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;

    final isLoggedIn = await AuthService.isLoggedIn();
    await AuthService.warmCache();

    print('onboardingSeen: $onboardingSeen, isLoggedIn: $isLoggedIn');

    setState(() {
      _initialScreen = !onboardingSeen
          ? const OnboardingScreen()
          : isLoggedIn
          ? const MainScreen()
          : const WelcomeScreen();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return ChangeNotifierProvider(
      create: (context) => UserBalanceProvider(),
      child: MaterialApp(
        title: 'AmSubNig',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        home: AppWrapper(child: _initialScreen!),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/main': (context) => const MainScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
        },
      ),
    );
  }
}