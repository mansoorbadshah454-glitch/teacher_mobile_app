import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    print("👋 [WelcomeScreen] InitState");
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Slower for effect
    );

    // Slide from 0 to -1 (Off screen to left)
    // Wait, the user wants "welcome screen animate to left to open dashboard screen".
    // This usually means the Welcome Screen slides OUT to the Left, revealing Dashboard.
    // OR Dashboard slides IN from Right.
    // Let's assume standard "Push" navigation where new screen comes from Right, 
    // effectively pushing old screen to Left.
    // BUT user said "animate to left".
    
    // Let's make it auto-navigate after a delay with a specific transition.

    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          // FORCE refresh the token to retrieve the latest Custom Claims
          final tokenResult = await user.getIdTokenResult(true);
          final claims = tokenResult.claims ?? {};
          
          if (!claims.containsKey('schoolId') || claims['schoolId'] == null) {
             print("🚨 [WelcomeScreen] User lacks schoolId claim! Forcing sign-out to prevent data leaks.");
             await FirebaseAuth.instance.signOut();
             if (mounted) context.go('/login');
             return;
          }
          
          print("🚀 [WelcomeScreen] User verified with schoolId: ${claims['schoolId']}. Navigating to /dashboard");
          if (mounted) context.go('/dashboard');
        } catch (e) {
          print("🚨 [WelcomeScreen] Token verification failed: $e");
          await FirebaseAuth.instance.signOut();
          if (mounted) context.go('/login');
        }
      } else {
         print("🔒 [WelcomeScreen] No user logged in. Navigating to /login");
         context.go('/login');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.primaryGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.school, // Placeholder for Graduation Cap
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 20),
              Text(
                "MAI SMS",
                style: AppTheme.displayLarge.copyWith(fontSize: 40),
              ),
              const SizedBox(height: 10),
              Text(
                "Teacher App",
                style: AppTheme.titleLarge.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(
                color: Colors.white,
              )
            ],
          ),
        ),
      ),
    );
  }
}
