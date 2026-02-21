import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/dashboard/presentation/widgets/app_drawer.dart';
import 'package:teacher_mobile_app/features/dashboard/presentation/widgets/stat_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool isOnDuty = false; // Local state for now

  @override
  Widget build(BuildContext context) {
    print("🏠 [Dashboard] Build Started");

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      drawer: const AppDrawer(),
      appBar: AppBar(
        // Removed Title / School Logo here
        actions: [
          // Duty Toggle
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Text(
                  isOnDuty ? "On Duty" : "Off Duty",
                  style: TextStyle(
                    color: isOnDuty ? Colors.greenAccent : Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: isOnDuty,
                  activeColor: Colors.greenAccent,
                  onChanged: (val) {
                    setState(() {
                      isOnDuty = val;
                      // Firestore update logic will go here
                    });
                  },
                ),
              ],
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Text(
              "Welcome back, ${FirebaseAuth.instance.currentUser?.displayName ?? 'Teacher'}!",
              style: AppTheme.displayLarge.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 4),
            Text(
              "Please start your day by toggling the Duty On button.",
              style: AppTheme.labelSmall.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Grid
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85, 
                children: [
                   StatCard(
                    title: "News Feed",
                    description: "School announcements",
                    icon: Icons.newspaper,
                    color: const Color(0xFF10b981), // Emerald
                    onTap: () => context.push('/news-feed'),
                    badgeCount: 2, // Mock unread
                  ),
                  StatCard(
                    title: "Attendance",
                    description: "Mark presence",
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF6366f1), // Indigo
                    onTap: () => context.push('/attendance'),
                  ),
                  StatCard(
                    title: "My Class",
                    description: "Update scores",
                    icon: Icons.bar_chart,
                    color: const Color(0xFF8b5cf6), // Violet
                    onTap: () => context.push('/my-class'),
                  ),
                  StatCard(
                    title: "Next Class",
                    description: "Subjects period",
                    icon: Icons.access_time,
                    color: const Color(0xFFf59e0b), // Amber
                    onTap: () => context.push('/next-class'),
                  ),
                  StatCard(
                    title: "Notebook",
                    description: "Private notes",
                    icon: Icons.book,
                    color: const Color(0xFFec4899), // Pink
                    onTap: () => context.push('/notebook'),
                  ),
                   StatCard(
                    title: "Contact Parents",
                    description: "Messages",
                    icon: Icons.people_outline,
                    color: const Color(0xFF3b82f6), // Blue
                    onTap: () => context.push('/contact-parents'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
