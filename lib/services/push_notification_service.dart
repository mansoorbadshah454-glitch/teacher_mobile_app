import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> init(String schoolId, String uid) async {
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
