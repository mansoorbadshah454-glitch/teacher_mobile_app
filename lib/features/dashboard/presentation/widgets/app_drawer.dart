import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolAsync = ref.watch(schoolDataProvider);

    final schoolName = schoolAsync.value?['name'] ?? 'School Name';
    final schoolLogo = schoolAsync.value?['logo'] ?? '';

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.background,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: Colors.white,
                        backgroundImage: schoolLogo.isNotEmpty 
                            ? CachedNetworkImageProvider(schoolLogo)
                            : null,
                        child: schoolLogo.isEmpty 
                            ? const Icon(Icons.school, size: 45, color: AppTheme.primary)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        schoolName,
                        textAlign: TextAlign.center,
                        style: AppTheme.titleLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ],
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
            onTap: () {
              Navigator.pop(context);
              context.push('/inbox'); // Push allows the device back button to work
            },
          ),
          _DrawerItem(
            icon: Icons.person_outline,
            title: 'Profile',
            onTap: () {
              Navigator.pop(context);
              context.push('/profile');
            },
          ),
          _DrawerItem(
            icon: Icons.contact_support_outlined,
            title: 'Contact Principal & Admins',
            onTap: () {
              Navigator.pop(context);
              context.push('/contact-admins');
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

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : AppTheme.primary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
