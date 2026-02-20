import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/theme_provider.dart';
import 'package:teacher_mobile_app/core/router/app_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

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
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Teacher App',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
