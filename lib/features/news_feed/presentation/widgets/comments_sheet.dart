import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  final String schoolId;
  final String postId;

  const CommentsSheet({
    super.key,
    required this.schoolId,
    required this.postId,
  });

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;
  
  String? _replyingToCommentId;
  String? _replyingToName;
  final Map<String, bool> _showReplies = {};

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception("User not logged in");

      final commentData = {
        'text': text,
        'authorId': user.uid,
        'authorName': user.displayName ?? "User",
        'authorImage': user.photoURL ?? "",
        'role': 'Teacher', // Can be dynamically set based on claims later
        'timestamp': FieldValue.serverTimestamp(),
        'likes': [],
      };

      final postRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('posts')
          .doc(widget.postId);

      if (_replyingToCommentId != null) {
        // Write to replies subcollection
        await postRef
            .collection('comments')
            .doc(_replyingToCommentId)
            .collection('replies')
            .add(commentData);
            
        // Increment reply count on parent comment
        await postRef.collection('comments').doc(_replyingToCommentId).update({
          'replyCount': FieldValue.increment(1)
        });
        
        setState(() {
          // Auto-expand replies to see what you just posted
          _showReplies[_replyingToCommentId!] = true;
          _replyingToCommentId = null;
          _replyingToName = null;
        });
      } else {
        // Write top-level comment
        await postRef.collection('comments').add(commentData);
        // Increment comment count on the post
        await postRef.update({
          'commentCount': FieldValue.increment(1)
        });
      }

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

  Future<void> _toggleCommentLike(String commentId, List<String> currentLikes) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final isLiked = currentLikes.contains(user.uid);
    final commentRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId);
        
    try {
      if (isLiked) {
        await commentRef.update({'likes': FieldValue.arrayRemove([user.uid])});
      } else {
        await commentRef.update({'likes': FieldValue.arrayUnion([user.uid])});
      }
    } catch (e) {
      print("Error liking comment: $e");
    }
  }

  Widget _buildRepliesList(String commentId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.only(top: 8), child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)));
        final replies = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: replies.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final time = data['timestamp'] as Timestamp?;
            final tString = time != null ? timeago.format(time.toDate()) : 'Now';
            
            return Padding(
               padding: const EdgeInsets.only(top: 6),
               child: Row(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    CircleAvatar(
                       radius: 10,
                       backgroundColor: Theme.of(context).primaryColor,
                       backgroundImage: data['authorImage'] != null && data['authorImage'].isNotEmpty ? NetworkImage(data['authorImage']) : null,
                       child: (data['authorImage'] == null || data['authorImage'].isEmpty) ? const Icon(Icons.person, size: 12, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                             decoration: BoxDecoration(
                               color: Theme.of(context).dividerColor.withOpacity(0.05),
                               borderRadius: BorderRadius.circular(12),
                             ),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                  Text(data['authorName'] ?? 'Unknown', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                                  if (data['studentContext'] != null || data['role'] != null) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        if (data['studentContext'] != null) ...[
                                          Flexible(
                                            child: Text(data['studentContext'], style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey[700], fontSize: 10), overflow: TextOverflow.ellipsis),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (data['role'] != null)
                                          Flexible(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).primaryColor.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                data['role'],
                                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 9) ?? TextStyle(fontSize: 9, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Text(data['text'] ?? '', style: Theme.of(context).textTheme.bodySmall),
                               ]
                             )
                           ),
                           Padding(
                             padding: const EdgeInsets.only(left: 4, top: 4),
                             child: Text(tString, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey, fontSize: 10)),
                           )
                        ]
                      )
                    )
                 ]
               )
            );
          }).toList(),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

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
                    
                    final likesList = List<String>.from(data['likes'] ?? []);
                    final isLiked = user != null && likesList.contains(user.uid);
                    final replyCount = data['replyCount'] ?? 0;
                    
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
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).dividerColor.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['authorName'] ?? 'Unknown',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      if (data['studentContext'] != null || data['role'] != null) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            if (data['studentContext'] != null) ...[
                                              Flexible(
                                                child: Text(data['studentContext'], style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey[700], fontSize: 11), overflow: TextOverflow.ellipsis),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            if (data['role'] != null)
                                              Flexible(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    data['role'],
                                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 10) ?? TextStyle(fontSize: 10, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        data['text'] ?? '',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 12, top: 2),
                                  child: Row(
                                    children: [
                                      Text(timeString, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey, fontSize: 11)),
                                      const SizedBox(width: 16),
                                      GestureDetector(
                                        onTap: () => _toggleCommentLike(comments[index].id, likesList),
                                        child: Text("Like", style: TextStyle(
                                            color: isLiked ? Theme.of(context).primaryColor : Colors.grey[600], 
                                            fontWeight: isLiked ? FontWeight.bold : FontWeight.w600,
                                            fontSize: 12
                                        )),
                                      ),
                                      if (likesList.isNotEmpty) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.thumb_up, size: 12, color: Theme.of(context).primaryColor),
                                        const SizedBox(width: 2),
                                        Text("${likesList.length}", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                                      ],
                                      if (likesList.isNotEmpty) ...[
                                        const SizedBox(width: 16),
                                        GestureDetector(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (_) => LikersDialog(uids: likesList),
                                            );
                                          },
                                          child: Text("View", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600, fontSize: 12)),
                                        ),
                                      ],
                                    ]
                                  ),
                                ),
                                if (replyCount > 0)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _showReplies[comments[index].id] = !(_showReplies[comments[index].id] ?? false);
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 6, left: 12),
                                      child: Text(
                                        (_showReplies[comments[index].id] ?? false) ? "Hide replies" : "View $replyCount replies",
                                        style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                
                                if (_showReplies[comments[index].id] ?? false)
                                   _buildRepliesList(comments[index].id),
                              ],
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_replyingToName != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Theme.of(context).dividerColor.withOpacity(0.05),
                    child: Row(
                      children: [
                        Text("Replying to ", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        Text("$_replyingToName", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() {
                            _replyingToCommentId = null;
                            _replyingToName = null;
                          }),
                          child: const Icon(Icons.close, size: 16, color: Colors.grey),
                        )
                      ],
                    ),
                  ),
                Container(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LikersDialog extends StatelessWidget {
  final List<String> uids;
  const LikersDialog({super.key, required this.uids});

  Future<List<String>> _fetchNames() async {
    List<String> names = [];
    for (String uid in uids) {
      try {
        final doc = await FirebaseFirestore.instance.collection('global_users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final name = data['name'] ?? data['displayName'] ?? 'Unknown User';
          String role = data['role']?.toString() ?? 'Teacher';
          if (role.isNotEmpty) {
            role = '${role[0].toUpperCase()}${role.substring(1)}';
          }
          names.add("$name ($role)");
        } else {
          // If not found in global_users, just use a placeholder
          names.add("Unknown User");
        }
      } catch (e) {
        names.add("Unknown User");
      }
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Reaction Details", style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<String>>(
          future: _fetchNames(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
              return const Text("Could not load likers.");
            }
            
            final names = snapshot.data!;
            return ListView.separated(
              shrinkWrap: true,
              itemCount: names.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                 return Padding(
                   padding: const EdgeInsets.symmetric(vertical: 4),
                   child: Text("${names[index]} liked this comment.", style: const TextStyle(fontSize: 14)),
                 );
              }
            );
          }
        )
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        )
      ],
    );
  }
}
