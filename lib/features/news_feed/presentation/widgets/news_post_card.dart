import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:teacher_mobile_app/core/theme/app_theme.dart'; // Ensure correct path
import 'package:teacher_mobile_app/features/news_feed/presentation/widgets/video_player_widget.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/screens/create_post_screen.dart'; // Import CreatePostScreen
import 'package:teacher_mobile_app/features/news_feed/presentation/widgets/comments_sheet.dart';
import 'package:firebase_storage/firebase_storage.dart';

class NewsPostCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  final String schoolId;

  const NewsPostCard({
    super.key,
    required this.id,
    required this.data,
    required this.schoolId,
  });

  @override
  State<NewsPostCard> createState() => _NewsPostCardState();
}

class _NewsPostCardState extends State<NewsPostCard> {
  // VideoPlayerController? _videoController;
  bool isLiked = false;
  int likeCount = 0;
  
  final List<List<Color>> _backgroundGradients = [
    [], // Default
    [const Color(0xFFFF5F6D), const Color(0xFFFFC371)], // Sunset
    [const Color(0xFF2193b0), const Color(0xFF6dd5ed)], // Ocean
    [const Color(0xFFcc2b5e), const Color(0xFF753a88)], // Purple Love
    [const Color(0xFF00B4DB), const Color(0xFF0083B0)], // Blue Raspberry
    [const Color(0xFFf12711), const Color(0xFFf5af19)], // Flare
    [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)], // Frost
  ];

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final likes = List<String>.from(widget.data['likes'] ?? []);
    isLiked = uid != null && likes.contains(uid);
    likeCount = likes.length;
  }

  @override
  void dispose() {
    // _videoController?.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final postRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('posts')
        .doc(widget.id);

    setState(() {
      isLiked = !isLiked;
      likeCount += isLiked ? 1 : -1;
    });

    try {
      if (isLiked) {
        await postRef.update({
          'likes': FieldValue.arrayUnion([user.uid])
        });
      } else {
        await postRef.update({
          'likes': FieldValue.arrayRemove([user.uid])
        });
      }
    } catch (e) {
      // Revert if failed
      setState(() {
        isLiked = !isLiked;
        likeCount += isLiked ? 1 : -1;
      });
      print("Error liking post: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final timestamp = data['timestamp'] as Timestamp?;
    final timeString = timestamp != null ? timeago.format(timestamp.toDate()) : 'Recently';
    final authorName = data['authorName'] ?? 'Unknown';
    final authorImage = data['authorImage'] ?? '';
    final role = data['role'] ?? 'Teacher';
    final text = data['text'] ?? '';
    final mediaUrl = data['mediaUrl'] ?? data['imageUrl']; // Fallback to legacy
    final mediaType = data['mediaType'] ?? (data['imageUrl'] != null ? 'image' : 'none');
    
    // Background style handling
    final bgIndex = data['backgroundIndex'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8), // Gap between posts
      color: AppTheme.surfaceDark, // Card background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: authorImage.isNotEmpty ? NetworkImage(authorImage) : null,
                  backgroundColor: AppTheme.primary,
                  child: authorImage.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text(
                          "$role • $timeString",
                          style: AppTheme.labelSmall,
                        ),
                        if (data['targetClassName'] != null && data['targetClassName'].isNotEmpty)
                           Text(
                            " • ${data['targetClassName']}",
                             style: AppTheme.labelSmall.copyWith(color: AppTheme.accent),
                           ),
                      ],
                    ),
                    if (timestamp != null)
                      Text(
                        "Expires ${timestamp.toDate().add(const Duration(days: 7)).toString().substring(0, 10)}",
                        style: AppTheme.labelSmall.copyWith(color: Colors.redAccent, fontSize: 10),
                      ),
                  ],
                ),
                const Spacer(),
                // Edit and Delete Options
                if (FirebaseAuth.instance.currentUser?.uid == data['authorId'] || true) // Assuming principals/teachers have rights based on rules
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: Colors.white54),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editPost();
                      } else if (value == 'delete') {
                        _deletePost();
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      return [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete'),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
              ],
            ),
          ),

          // Text Content
          if (text.isNotEmpty)
            if (bgIndex != 0 && bgIndex < _backgroundGradients.length)
              Container(
                width: double.infinity,
                height: 300,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _backgroundGradients[bgIndex]),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  text,
                  style: AppTheme.bodyMedium,
                ),
              ),
          
          const SizedBox(height: 8),

          // Media Content
          if (mediaType == 'image' && mediaUrl != null && mediaUrl.isNotEmpty)
            GestureDetector(
                onTap: () {
                    // Open full screen image
                    showDialog(context: context, builder: (_) => Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: EdgeInsets.zero,
                        child: InteractiveViewer(
                            child: CachedNetworkImage(imageUrl: mediaUrl),
                        ),
                    ));
                },
                child: CachedNetworkImage(
                  imageUrl: mediaUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                      height: 200, 
                      color: Colors.white10, 
                      child: const Center(child: CircularProgressIndicator())
                  ),
                  errorWidget: (context, url, error) => const SizedBox(),
                ),
            ),
            
          // Video Content
          if (mediaType == 'video' && mediaUrl != null && mediaUrl.isNotEmpty)
            VideoPlayerWidget(videoUrl: mediaUrl),

          // Stats (Likes/Comments)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                if (likeCount > 0) ...[
                    const Icon(Icons.thumb_up, size: 14, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text("$likeCount", style: AppTheme.labelSmall),
                ],
                const Spacer(),
                Text("${data['commentCount'] ?? 0} comments", style: AppTheme.labelSmall),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: _toggleLike,
                  icon: Icon(
                      isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                      color: isLiked ? AppTheme.primary : Colors.white70,
                      size: 18
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                        "Like",
                        style: TextStyle(
                            color: isLiked ? AppTheme.primary : Colors.white70,
                        )
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => SizedBox(
                          height: MediaQuery.of(context).size.height * 0.75,
                          child: CommentsSheet(
                            schoolId: widget.schoolId,
                            postId: widget.id,
                          ),
                        ),
                      );
                  },
                  icon: const Icon(Icons.mode_comment_outlined, color: Colors.white70, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("Comment", style: TextStyle(color: Colors.white70))
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () {},
                  icon: const Icon(Icons.share_outlined, color: Colors.white70, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("Share", style: TextStyle(color: Colors.white70))
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
  void _deletePost() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text("Delete Post", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to delete this post?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              try {
                // Delete from Firestore
                await FirebaseFirestore.instance
                    .collection('schools')
                    .doc(widget.schoolId)
                    .collection('posts')
                    .doc(widget.id)
                    .delete();
                
                // Optional: Delete media from Storage if exists (requires reference)
                if (widget.data['mediaUrl'] != null) {
                   try {
                     await FirebaseStorage.instance.refFromURL(widget.data['mediaUrl']).delete();
                   } catch (e) {
                     print("Error deleting media: $e");
                     // Continue even if media delete fails
                   }
                }

              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error deleting post: $e")),
                );
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _editPost() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreatePostScreen(
            schoolId: widget.schoolId,
            postId: widget.id,
            initialData: widget.data,
          ),
        ),
      );
  }
}

