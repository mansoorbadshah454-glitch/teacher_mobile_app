import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/theme_provider.dart';
import 'package:teacher_mobile_app/core/router/app_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:teacher_mobile_app/services/push_notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    
    final data = message.data;
    final title = data['title'] ?? message.notification?.title ?? 'New Notification';
    final body = data['body'] ?? message.notification?.body ?? 'You have a new update';
    final type = data['type'] ?? 'info';
    
    bool isEmergency = type == 'timetable_update' && title.toString().toLowerCase().contains('urgent');

    if (isEmergency) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('timetable_emergency_message', body.isEmpty ? 'Emergency Timetable update received.' : body);
      await prefs.setString('timetable_emergency_date', DateTime.now().toIso8601String());
    }

    final FlutterLocalNotificationsPlugin localNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await localNotificationsPlugin.initialize(initializationSettings);

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      isEmergency ? 'emergency_channel' : 'high_importance_channel',
      isEmergency ? 'Emergency Alerts' : 'Important Notifications',
      channelDescription: 'Used for important teacher app notifications.',
      importance: isEmergency ? Importance.max : Importance.high,
      priority: isEmergency ? Priority.max : Priority.high,
      enableVibration: true,
      playSound: true,
    );

    NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    // Only show a local notification if it's a data-only message.
    // If message.notification is not null, FCM automatically displays a system notification.
    if (message.notification == null) {
      await localNotificationsPlugin.show(
        message.messageId.hashCode,
        title,
        body,
        platformDetails,
        payload: type,
      );
    }
  } catch (e) {
    print("Background Isolate Crash Prevented: $e");
  }
}

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    print("🚀 [Main] Flutter Binding Initialized");
    
    print("🚀 [Main] Flutter Binding Initialized");
    
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(); // Uses google-services.json on Android
        print("🔥 [Main] Firebase Initialized (Native)");
      } else {
        print("🔥 [Main] Firebase already initialized");
      }

      // Enable aggressive offline persistence
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      print("💽 [Main] Firestore Offline Persistence Enabled");
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      FirebaseMessaging.instance.getInitialMessage().then((message) {
         if (message != null) {
            /* Adding a standard 1.5s delay to assure the app finishes mounting the widget root 
               and finishes Firebase Auth restoration before actively jumping. */
            Future.delayed(const Duration(milliseconds: 1500), () {
               final type = message.data['type'];
               final route = PushNotificationService.getRouteFromType(type);
               if (route != null) {
                   appRouter.push(route);
               }
            });
         }
      }).catchError((e) {
          print("💥 [Main] getInitialMessage Error: $e");
      });
    } catch (e) {
      print("💥 [Main] Firebase Init Error: $e");
    }

    runApp(
      const ProviderScope(
        child: TeacherApp(),
      ),
    );
     print("🎨 [Main] App Runner Started");
  }, (error, stack) {
    print("💥 [Main] Uncaught Error: $error");
    print(stack);
  });
}

class TeacherApp extends ConsumerWidget {
  const TeacherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Teacher App',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
    );
  }
}
