import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/router/app_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
// import 'package:teacher_mobile_app/firebase_options.dart';

import 'dart:async';

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
    return MaterialApp.router(
      title: 'Teacher App',
      theme: AppTheme.darkTheme, // Default to dark as per webapp
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Enforce dark for now to match "Modern Prime" look
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
