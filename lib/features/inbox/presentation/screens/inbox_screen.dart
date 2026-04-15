import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/dashboard/presentation/widgets/app_drawer.dart';
import 'package:teacher_mobile_app/core/providers/admin_data_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:teacher_mobile_app/features/inbox/presentation/screens/chat_screen.dart';
import 'package:teacher_mobile_app/features/inbox/providers/inbox_provider.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminsAsync = ref.watch(adminsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.secondary,
            elevation: 0,
            title: const Text(
              'Inbox',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          adminsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            ),
            error: (err, stack) => SliverFillRemaining(
              child: Center(child: Text('Error loading admins: $err')),
            ),
            data: (admins) {
              if (admins.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: Text("No admins found.")),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final admin = admins[index];
                      return _AdminProfileTile(admin: admin);
                    },
                    childCount: admins.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminProfileTile extends ConsumerWidget {
  final Map<String, dynamic> admin;

  const _AdminProfileTile({required this.admin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Calculate unread count for this specific admin
    final messagesAsync = ref.watch(inboxProvider);
    int unreadCount = 0;
    if (messagesAsync.value != null) {
      unreadCount = messagesAsync.value!.where((msg) {
        if (msg['read'] == true) return false;
        final fromId = msg['fromId'] ?? msg['from'];
        return fromId == admin['id'];
      }).length;
    }

    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primary.withOpacity(0.1),
            backgroundImage: admin['photo'].isNotEmpty 
                ? CachedNetworkImageProvider(admin['photo'])
                : null,
            child: admin['photo'].isEmpty 
                ? const Icon(Icons.person, color: AppTheme.primary, size: 30)
                : null,
          ),
          if (admin['type'] == 'principal')
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield, color: AppTheme.accent, size: 14),
              ),
            ),
        ],
      ),
      title: Text(
        admin['name'],
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        admin['role'],
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Icon(Icons.chevron_right, color: isDark ? Colors.grey[700] : Colors.grey[400]),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(admin: admin),
          ),
        );
      },
    );
  }
}
