import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:teacher_mobile_app/core/router/app_router.dart';

import 'package:teacher_mobile_app/core/theme/app_theme.dart';

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Route resolution
  static String? getRouteFromType(String? type) {
    if (type == null) return null;
    switch (type) {
      case 'timetable_update': return '/timetable';
      case 'news_feed': return '/news-feed';
      case 'admin_msg': return '/inbox';
      case 'chat_message': return '/inbox';
      case 'notebook_alert': return '/notebook';
      default: return null;
    }
  }

  static void showGlobalAlert(String title, String body, String? route, {bool isEmergency = false}) {
    final context = rootScaffoldMessengerKey.currentContext;
    if (context != null) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
               if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: Colors.white)),
               ]
            ]
          ),
          backgroundColor: isEmergency ? Colors.red.shade600 : AppTheme.primary,
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.horizontal,
          action: route != null ? SnackBarAction(
            label: "VIEW", 
            textColor: Colors.white, 
            onPressed: () {
               appRouter.push(route);
            }
          ) : null,
        )
      );
    }
  }

  Future<void> init(String schoolId, String uid, {Function(String type, String title, String body)? onMessageAlert}) async {
    // Request permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
      // Get the token
      String? token = await _fcm.getToken();
      if (token != null) {
         await saveTokenToDatabase(token, schoolId, uid);
      }

      // Any time the token refreshes, store this in the database too.
      _fcm.onTokenRefresh.listen((newToken) {
         saveTokenToDatabase(newToken, schoolId, uid);
      });

      // Foreground message handler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        print('Got a message whilst in the foreground!');

        if (message.notification != null) {
          final title = message.notification?.title ?? 'Notification';
          final body = message.notification?.body ?? '';
          final type = message.data['type'] ?? '';
          
          if (onMessageAlert != null) {
            onMessageAlert(type, title, body);
          } else {
            // Fallback: Write directly to disk and show alert if callback fails
            bool isEmergency = false;
            if (type == 'timetable_update' && title.contains('Urgent') == true) {
              isEmergency = true;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('timetable_emergency_message', body.isEmpty ? 'Emergency Timetable update received.' : body);
              await prefs.setString('timetable_emergency_date', DateTime.now().toIso8601String());
            }

            final route = getRouteFromType(type);
            showGlobalAlert(title, body, route, isEmergency: isEmergency);
          }
        }
      });
      
      // Background message tap handler
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
         final type = message.data['type'];
         final route = getRouteFromType(type);
         
         // Trigger the callback if it was an emergency timetable
         if (onMessageAlert != null && message.notification != null) {
            final title = message.notification?.title ?? '';
            final body = message.notification?.body ?? '';
            if (type == 'timetable_update' && title.contains('Urgent')) {
               onMessageAlert(type!, title, body);
            }
         }

         if (route != null) {
            appRouter.push(route);
         }
      });
      
    } else {
      print('User declined or has not accepted permission');
    }
  }

  Future<void> saveTokenToDatabase(String token, String schoolId, String uid) async {
    try {
      await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .doc(uid)
        .set({
          'fcmToken': FieldValue.arrayUnion([token]),
        }, SetOptions(merge: true));
        print('FCM Token saved successfully');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }
}
