import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/inbox/providers/inbox_provider.dart';
import 'package:teacher_mobile_app/features/timetable/providers/timetable_provider.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolAsync = ref.watch(schoolDataProvider);
    final messagesAsync = ref.watch(inboxProvider);
    final hasTimetableStar = ref.watch(hasUnreadEmergencyProvider);

    final schoolName = schoolAsync.value?['name'] ?? 'School Name';
    final schoolLogo = schoolAsync.value?['logo'] ?? '';
    
    int unreadCount = 0;
    if (messagesAsync.value != null) {
      unreadCount = messagesAsync.value!.where((msg) => msg['read'] == false).length;
    }

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.background,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 24.0,
              bottom: 24.0,
              left: 16.0,
              right: 16.0,
            ),
            margin: const EdgeInsets.only(bottom: 8.0),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 54, // Increased logo size
                  backgroundColor: Colors.white,
                  backgroundImage: schoolLogo.isNotEmpty 
                      ? CachedNetworkImageProvider(schoolLogo)
                      : null,
                  child: schoolLogo.isEmpty 
                      ? const Icon(Icons.school, size: 55, color: AppTheme.primary)
                      : null,
                ),
                const SizedBox(height: 8), // Slightly reduced spacing to balance the larger logo
                Text(
                  schoolName,
                  textAlign: TextAlign.center,
                  style: AppTheme.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Teacher's Smart Portal",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _DrawerItem(
            icon: Icons.home_outlined,
            title: 'Home',
            onTap: () {
              Navigator.pop(context);
              context.go('/dashboard'); // Go explicitly clears the stack to return to root
            },
          ),
          _DrawerItem(
            icon: Icons.inbox_outlined,
            title: 'Inbox',
            badgeCount: unreadCount,
            onTap: () {
              Navigator.pop(context);
              context.push('/inbox'); // Push allows the device back button to work
            },
          ),
          _DrawerItem(
            icon: Icons.co_present,
            title: 'Attendance',
            onTap: () {
              Navigator.pop(context);
              context.push('/teacher-attendance');
            },
          ),
          _DrawerItem(
            icon: Icons.calendar_month_outlined,
            title: 'Time table',
            showStarBadge: hasTimetableStar,
            onTap: () async {
              Navigator.pop(context);
              await ref.read(emergencyBadgeProvider.notifier).reload();
              if (context.mounted) context.push('/timetable');
            },
          ),
          _DrawerItem(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () {
              Navigator.pop(context);
              context.push('/settings');
            },
          ),
          const Divider(height: 32, thickness: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.accent),
            title: const Text('Logout', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(context); // Close drawer
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final int badgeCount;
  final bool showStarBadge;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.badgeCount = 0,
    this.showStarBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : AppTheme.primary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
              if (showStarBadge)
                const Padding(
                  padding: EdgeInsets.only(left: 6.0),
                  child: Icon(Icons.star, color: Colors.amber, size: 16),
                ),
            ],
          ),
          if (badgeCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badgeCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
