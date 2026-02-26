import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/dashboard/presentation/widgets/app_drawer.dart';
import 'package:teacher_mobile_app/features/dashboard/presentation/widgets/stat_card.dart';
import 'package:teacher_mobile_app/features/dashboard/providers/unread_news_feed_provider.dart';

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
    
    // Watch unread news feed count
    final unreadCountAsyncValue = ref.watch(unreadNewsFeedProvider);
    final unreadCount = unreadCountAsyncValue.when(
      data: (count) => count,
      loading: () => 0,
      error: (_, __) => 0,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        // Removed Title / School Logo here
        backgroundColor: Colors.transparent, // Let Container gradient show through
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white), // Forces Drawer Icon to be White
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
            ],
          ),
        ),
        actions: [
          // Duty Toggle
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Text(
                  isOnDuty ? "On Duty" : "Off Duty",
                  style: TextStyle(
                    color: isOnDuty ? Colors.green : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: isOnDuty,
                  activeColor: Colors.white, // The dot when ON
                  activeTrackColor: Colors.green, // The background when ON
                  inactiveThumbColor: Colors.white, // The dot when OFF
                  inactiveTrackColor: Colors.white24, // The background when OFF
                  trackOutlineColor: MaterialStateProperty.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return Colors.green; // Outline when ON
                    }
                    return Colors.white; // Outline when OFF
                  }),
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
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome back, ${FirebaseAuth.instance.currentUser?.displayName ?? 'Teacher'}!",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ) ?? TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                ),
                const SizedBox(height: 2),
                Text(
                  "Please start your day by toggling the Duty On button.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12) ?? const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
                    badgeCount: unreadCount, // Dynamic unread count
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
