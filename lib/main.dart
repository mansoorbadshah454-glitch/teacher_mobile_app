import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/theme_provider.dart';
import 'package:teacher_mobile_app/core/router/app_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teacher_mobile_app/services/push_notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] == 'timetable_update' && message.notification?.title?.contains('Urgent') == true) {
    final body = message.notification?.body ?? 'Emergency Timetable update received.';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timetable_emergency_message', body);
    await prefs.setString('timetable_emergency_date', DateTime.now().toIso8601String());
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
