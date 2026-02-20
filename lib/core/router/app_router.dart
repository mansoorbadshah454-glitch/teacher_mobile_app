import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:teacher_mobile_app/features/auth/presentation/screens/login_screen.dart';
import 'package:teacher_mobile_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:teacher_mobile_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:teacher_mobile_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/screens/news_feed_screen.dart';
import 'package:teacher_mobile_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:teacher_mobile_app/features/contact/presentation/screens/contact_admins_screen.dart';
import 'package:teacher_mobile_app/features/attendance/presentation/screens/attendance_screen.dart';
import 'package:teacher_mobile_app/features/attendance/presentation/screens/attendance_report_screen.dart';
import 'package:teacher_mobile_app/features/my_class/presentation/screens/my_class_screen.dart';
import 'package:teacher_mobile_app/features/my_class/presentation/screens/student_performance_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/welcome',
  routes: [
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      pageBuilder: (context, state) {
        return CustomTransitionPage(
          key: state.pageKey,
          child: const DashboardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Slide transition: Dashboard slides in from Right, pushing Welcome to Left.
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;

            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/news-feed',
      builder: (context, state) => const NewsFeedScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/contact-admins',
      builder: (context, state) => const ContactAdminsScreen(),
    ),
    GoRoute(
      path: '/attendance',
      builder: (context, state) => const AttendanceScreen(),
    ),
    GoRoute(
      path: '/attendance-report',
      builder: (context, state) => const AttendanceReportScreen(),
    ),
    GoRoute(
      path: '/my-class',
      builder: (context, state) => const MyClassScreen(),
    ),
    GoRoute(
      path: '/my-class/student/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return StudentPerformanceScreen(studentId: id);
      },
    ),
  ],
);
