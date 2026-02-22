import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;

class CommentsSheet extends StatefulWidget {
  final String schoolId;
  final String postId;

  const CommentsSheet({
    super.key,
    required this.schoolId,
    required this.postId,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      final commentData = {
        'text': text,
        'authorId': user.uid,
        'authorName': user.displayName ?? "User",
        'authorImage': user.photoURL ?? "",
        'role': 'Teacher', // Can be dynamically set based on claims later
        'timestamp': FieldValue.serverTimestamp(),
      };

      final postRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('posts')
          .doc(widget.postId);

      // Write the comment to subcollection
      await postRef.collection('comments').add(commentData);

      // Increment comment count on the post
      await postRef.update({
        'commentCount': FieldValue.increment(1)
      });

      _commentController.clear();
      // Dismiss keyboard
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error posting comment: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsQuery = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .orderBy('timestamp', descending: true);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          Text("Comments", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          Divider(color: Theme.of(context).dividerColor),

          // Comments List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: commentsQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                }

                final comments = snapshot.data?.docs ?? [];

                if (comments.isEmpty) {
                  return Center(
                    child: Text(
                      "No comments yet. Be the first to comment!",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
                          ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final data = comments[index].data() as Map<String, dynamic>;
                    final timestamp = data['timestamp'] as Timestamp?;
                    final timeString = timestamp != null ? timeago.format(timestamp.toDate()) : 'Just now';
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Theme.of(context).primaryColor,
                            backgroundImage: data['authorImage'] != null && data['authorImage'].isNotEmpty
                                ? NetworkImage(data['authorImage'])
                                : null,
                            child: (data['authorImage'] == null || data['authorImage'].isEmpty)
                                ? const Icon(Icons.person, color: Colors.white, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).dividerColor.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            data['authorName'] ?? 'Unknown',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            data['role'] ?? 'Teacher',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: Theme.of(context).textTheme.labelSmall?.color?.withOpacity(0.6),
                                                ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        timeString,
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: Theme.of(context).textTheme.labelSmall?.color?.withOpacity(0.4),
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    data['text'] ?? '',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Comment Input
          SafeArea(
            bottom: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: "Write a comment...",
                        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.4),
                            ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: (_commentController.text.trim().isNotEmpty && !_isSubmitting)
                        ? _submitComment
                        : null,
                    icon: _isSubmitting 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            Icons.send,
                            color: _commentController.text.trim().isNotEmpty 
                                ? Theme.of(context).primaryColor 
                                : Theme.of(context).disabledColor,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
