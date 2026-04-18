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
  bool _isInitialized = false;

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

  static OverlayEntry? _currentBanner;

  static void showGlobalAlert(String title, String body, String? route, {bool isEmergency = false}) {
    // Get reliable context for theme/media queries
    final context = rootScaffoldMessengerKey.currentContext ?? appRouter.routerDelegate.navigatorKey.currentContext;
    // Get reliable overlay state directly from GoRouter's internal root navigator
    final overlayState = appRouter.routerDelegate.navigatorKey.currentState?.overlay;

    if (context != null && overlayState != null) {
      if (_currentBanner != null) {
        _currentBanner?.remove();
        _currentBanner = null;
      }
      
      _currentBanner = OverlayEntry(
        builder: (ctx) => AnimatedTopBanner(
          title: title,
          body: body,
          route: route,
          isEmergency: isEmergency,
          onDismissed: () {
            if (_currentBanner != null) {
               _currentBanner?.remove();
               _currentBanner = null;
            }
          },
        )
      );
      overlayState.insert(_currentBanner!);
    }
  }

  Future<void> init(String schoolId, String uid, {Function(String type, String title, String body)? onMessageAlert}) async {
    if (_isInitialized) return;
    
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
      
      _isInitialized = true;
      
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

class AnimatedTopBanner extends StatefulWidget {
  final String title;
  final String body;
  final String? route;
  final bool isEmergency;
  final VoidCallback onDismissed;

  const AnimatedTopBanner({
    Key? key,
    required this.title,
    required this.body,
    this.route,
    this.isEmergency = false,
    required this.onDismissed,
  }) : super(key: key);

  @override
  State<AnimatedTopBanner> createState() => _AnimatedTopBannerState();
}

class _AnimatedTopBannerState extends State<AnimatedTopBanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       duration: const Duration(milliseconds: 400),
       vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    // Hold the banner for 4 seconds then reverse
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && !_isDismissed) {
         _controller.reverse().then((value) {
            if (!_isDismissed) {
               _isDismissed = true;
               widget.onDismissed();
            }
         });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismissBanner() {
    if (!_isDismissed) {
      _isDismissed = true;
      _controller.reverse().then((_) {
        widget.onDismissed();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // SafeArea automatically prevents overlapping with the status bar icons
      child: SafeArea(
        child: SlideTransition(
          position: _offsetAnimation,
          child: Dismissible(
            key: UniqueKey(),
            direction: DismissDirection.up,
            onDismissed: (_) {
              if (!_isDismissed) {
                 _isDismissed = true;
                 widget.onDismissed();
              }
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                   color: widget.isEmergency ? Colors.red.shade600 : AppTheme.primary,
                   borderRadius: BorderRadius.circular(12),
                   boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 10)],
                ),
                child: ListTile(
                   contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                   title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                   subtitle: widget.body.isNotEmpty ? Padding(
                     padding: const EdgeInsets.only(top: 4),
                     child: Text(widget.body, style: const TextStyle(color: Colors.white)),
                   ) : null,
                   trailing: widget.route != null ? TextButton(
                     onPressed: () {
                        _dismissBanner();
                        appRouter.push(widget.route!);
                     },
                     style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                     ),
                     child: const Text("VIEW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                   ) : IconButton(
                     icon: const Icon(Icons.close, color: Colors.white),
                     onPressed: _dismissBanner,
                   ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


