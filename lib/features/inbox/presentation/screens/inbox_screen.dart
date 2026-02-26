import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/dashboard/presentation/widgets/app_drawer.dart';
import 'package:teacher_mobile_app/features/inbox/providers/inbox_provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messagesAsync = ref.watch(inboxProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
                ],
              ),
            ),
            title: const Text(
              'Inbox',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          messagesAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            ),
            error: (err, stack) => SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Error loading messages:\n$err',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
            ),
            data: (messages) {
              if (messages.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 80,
                          color: isDark ? Colors.grey[700] : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No messages yet.",
                          style: TextStyle(
                            fontSize: 18,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final msg = messages[index];
                      return _MessageCard(msg: msg);
                    },
                    childCount: messages.length,
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

class _MessageCard extends ConsumerWidget {
  final Map<String, dynamic> msg;

  const _MessageCard({required this.msg});

  Future<void> _deleteMessage(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
       try {
          final rawData = await ref.read(teacherDataProvider.future);
          final Map<String, dynamic>? userData = rawData; // teacherDataProvider already returns Map<String, dynamic>?
          final schoolId = userData?['schoolId'];
          if (schoolId != null) {
              await FirebaseFirestore.instance
                 .collection('schools')
                 .doc(schoolId)
                 .collection('messages')
                 .doc(msg['id'])
                 .delete();
              
              if (context.mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message deleted successfully')),
                 );
              }
          }
       } catch (e) {
          if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete message: $e')),
              );
          }
       }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUnread = msg['read'] == false;
    
    // Format timestamp securely
    String formattedTime = '';
    if (msg['timestamp'] != null) {
        if (msg['timestamp'] is Timestamp) {
            final DateTime dt = (msg['timestamp'] as Timestamp).toDate();
            formattedTime = DateFormat('MMM d, h:mm a').format(dt);
        } else if (msg['timestamp'] is String) {
            formattedTime = msg['timestamp']; // Fallback
        }
    }

    return Card(
      elevation: 0,
      color: isDark ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isUnread 
              ? AppTheme.primary.withOpacity(0.5) 
              : (isDark ? Colors.grey[800]! : Colors.grey[200]!),
          width: isUnread ? 1.5 : 1.0,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    child: const Icon(Icons.shield, color: AppTheme.primary, size: 20),
                 ),
                 const SizedBox(width: 12),
                 Expanded(
                    child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                             Flexible(
                               child: Text(
                                 msg['fromName'] ?? 'Principal',
                                 style: TextStyle(
                                   fontSize: 16,
                                   fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                                   color: isDark ? Colors.white : Colors.black87,
                                 ),
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ),
                             if (formattedTime.isNotEmpty)
                               Text(
                                 formattedTime,
                                 style: TextStyle(
                                   fontSize: 12,
                                   color: isDark ? Colors.grey[500] : Colors.grey[500],
                                 ),
                               )
                           ],
                         ),
                         const SizedBox(height: 2),
                         Row(
                            children: [
                              Text(
                                'Role: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                              Text(
                                msg['from']?.toString().toUpperCase() ?? 'ADMIN',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                         ),
                       ],
                    ),
                 ),
                 IconButton(
                    onPressed: () => _deleteMessage(context, ref),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Delete Message',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                 )
              ],
            ),
            const SizedBox(height: 12),
            Text(
               msg['text'] ?? '',
               style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: isDark ? Colors.grey[300] : Colors.black87,
               ),
            ),
          ],
        ),
      ),
    );
  }
}
