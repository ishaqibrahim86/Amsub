import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../screens/notifications_screen.dart';   // ← only for NotificationStore

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static const String _baseUrl = 'https://amsubnig.com';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'amsubnig_channel',
    'Amsubnig Notifications',
    description: 'Wallet funding and transaction alerts',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _saveTokenToServer();

    _messaging.onTokenRefresh.listen((newToken) {
      _sendTokenToServer(newToken);
    });

    // Foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _showLocalNotification(message);
      final String msg = message.notification?.body ?? message.notification?.title ?? 'New notification';
      await NotificationStore.addNotification(msg);
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  static void _showLocalNotification(RemoteMessage message) { /* unchanged */
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static void _handleNotificationTap(RemoteMessage message) {
    // Navigate later if you want
  }

  static Future<void> _saveTokenToServer() async { /* unchanged */
    try {
      final token = await _messaging.getToken();
      if (token != null) await _sendTokenToServer(token);
    } catch (e) {
      print('FCM token error: $e');
    }
  }

  static Future<void> _sendTokenToServer(String fcmToken) async { /* unchanged */
    try {
      final authToken = await AuthService.getToken();
      if (authToken == null || authToken.isEmpty) return;

      await http.post(
        Uri.parse('$_baseUrl/api/save-fcm-token/'),
        headers: {
          'Authorization': 'Token $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcm_token': fcmToken}),
      );
    } catch (e) {
      print('Save FCM token error: $e');
    }
  }
}