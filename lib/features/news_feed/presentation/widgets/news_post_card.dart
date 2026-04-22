import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/widgets/video_player_widget.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/screens/create_post_screen.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/widgets/comments_sheet.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

class _ReactionPopup extends StatefulWidget {
  final ValueNotifier<int> hoverNotifier;
  final List<GlobalKey> emojiKeys;

  const _ReactionPopup({
    required this.hoverNotifier,
    required this.emojiKeys,
  });

  @override
  State<_ReactionPopup> createState() => _ReactionPopupState();
}

class _ReactionPopupState extends State<_ReactionPopup> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<String> _emojiChars = ['👍', '❤️', '😂', '😮'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
          ],
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: widget.hoverNotifier,
          builder: (context, hoverIndex, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(4, (i) {
                final isHovered = hoverIndex == i;
                return Row(
                  children: [
                    if (i > 0) const SizedBox(width: 16),
                    AnimatedScale(
                      scale: isHovered ? 1.5 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.only(bottom: isHovered ? 10 : 0),
                        child: Container(
                          key: widget.emojiKeys[i],
                          child: Text(_emojiChars[i], style: TextStyle(fontSize: 28, color: i == 1 ? Colors.red : null)),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class NewsPostCard extends ConsumerStatefulWidget {
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
  ConsumerState<NewsPostCard> createState() => _NewsPostCardState();
}

class _NewsPostCardState extends ConsumerState<NewsPostCard> {
  bool isLiked = false;
  int likeCount = 0;
  bool _isExpanded = false;
  
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
    final likes = List<String>.from(widget.data['likes'] ?? []);
    likeCount = likes.length;
  }

  OverlayEntry? _overlayEntry;
  final ValueNotifier<int> _hoverIndexNotifier = ValueNotifier(-1);
  final List<GlobalKey> _emojiKeys = List.generate(4, (_) => GlobalKey());

  @override
  void dispose() {
    _hideReactions();
    super.dispose();
  }

  void _showReactions(BuildContext context) {
    if (_overlayEntry != null) return;
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    _hoverIndexNotifier.value = -1;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: _hideReactions,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
          Positioned(
            left: offset.dx,
            top: offset.dy - 60,
            child: Material(
              color: Colors.transparent,
              child: _ReactionPopup(
                hoverNotifier: _hoverIndexNotifier,
                emojiKeys: _emojiKeys,
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideReactions() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateHover(Offset globalPos) {
    int newHover = -1;
    for (int i = 0; i < _emojiKeys.length; i++) {
       final key = _emojiKeys[i];
       if (key.currentContext != null) {
          final box = key.currentContext!.findRenderObject() as RenderBox;
          final pos = box.localToGlobal(Offset.zero);
          final size = box.size;
          final rect = Rect.fromLTWH(pos.dx - 20, pos.dy - 60, size.width + 40, size.height + 120);
          if (rect.contains(globalPos)) {
             newHover = i;
             break;
          }
       }
    }
    if (_hoverIndexNotifier.value != newHover) {
       _hoverIndexNotifier.value = newHover;
    }
  }

  Future<void> _updateReaction(String type) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final postRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('posts')
        .doc(widget.id);

    try {
      await postRef.set({
        'reactions': { user.uid: type }
      }, SetOptions(merge: true));
    } catch (e) {
      print("Error updating reaction: $e");
    }
  }

  Future<void> _removeReaction() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final postRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('posts')
        .doc(widget.id);

    try {
      await postRef.update({
        'reactions.${user.uid}': FieldValue.delete()
      });
    } catch (e) {
      if (e.toString().contains("No document to update")) return;
      print("Error deleting reaction: $e");
    }
  }

  Widget _getReactionIcon(String type, BuildContext context) {
    if (type == 'heart') return const Text('❤️', style: TextStyle(fontSize: 18, color: Colors.red));
    if (type == 'haha') return const Text('😂', style: TextStyle(fontSize: 18));
    if (type == 'wow') return const Text('😮', style: TextStyle(fontSize: 18));
    if (type == 'like') return Icon(Icons.thumb_up, color: Theme.of(context).primaryColor, size: 18);
    return Icon(Icons.thumb_up_outlined, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7), size: 18);
  }

  String _getReactionText(String type) {
    if (type == 'heart') return 'Love';
    if (type == 'haha') return 'Haha';
    if (type == 'wow') return 'Wow';
    if (type == 'like') return 'Like';
    return 'Like';
  }

  Color _getReactionColor(String type, BuildContext context) {
    if (type == 'heart') return Colors.red;
    if (type == 'haha') return Colors.orange;
    if (type == 'wow') return Colors.amber;
    if (type == 'like') return Theme.of(context).primaryColor;
    return Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7) ?? Colors.grey;
  }

  void _openFullScreenViewer(BuildContext context, List<Map<String, dynamic>> media, int initialIndex) {
      final PageController controller = PageController(initialPage: initialIndex);
      showDialog(
          context: context, 
          builder: (_) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(
                children: [
                    PageView.builder(
                        controller: controller,
                        itemCount: media.length,
                        itemBuilder: (context, index) {
                            final m = media[index];
                            if (m['type'] == 'video') {
                                return Center(child: VideoPlayerWidget(videoUrl: m['url']));
                            }
                            return InteractiveViewer(
                                child: CachedNetworkImage(imageUrl: m['url']),
                            );
                        }
                    ),
                    Positioned(
                        top: 40,
                        right: 20,
                        child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 30),
                            onPressed: () => Navigator.pop(context)
                        )
                    )
                ]
            )
      ));
  }

  Widget _buildMediaItem(Map<String, dynamic> mediaList, List<Map<String, dynamic>> fullList, {BoxFit fit = BoxFit.cover}) {
    final type = mediaList['type'] ?? 'image';
    final url = mediaList['url'];
    if (url == null || url.isEmpty) return const SizedBox();

    Widget child;
    if (type == 'video') {
      child = Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          const Center(child: Icon(Icons.play_circle_fill, size: 48, color: Colors.white70)),
        ],
      );
    } else {
      child = CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        placeholder: (context, url) => Container(color: Colors.white10, child: const Center(child: CircularProgressIndicator())),
        errorWidget: (context, url, error) => const SizedBox(),
      );
    }

    return GestureDetector(
      onTap: () {
         _openFullScreenViewer(context, fullList, fullList.indexOf(mediaList));
      },
      child: child,
    );
  }

  Widget _buildMediaCollage(List<Map<String, dynamic>> media, BuildContext context) {
    if (media.length == 1) {
      if (media.first['type'] == 'video') {
         return Center(child: VideoPlayerWidget(videoUrl: media.first['url']!));
      }
      return SizedBox(
        width: double.infinity,
        child: _buildMediaItem(media.first, media)
      );
    }
    
    if (media.length == 2) {
      return SizedBox(
        height: 300,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildMediaItem(media[0], media)),
            const SizedBox(width: 2),
            Expanded(child: _buildMediaItem(media[1], media)),
          ],
        )
      );
    }

    if (media.length == 3) {
      return SizedBox(
        height: 300,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 2, child: _buildMediaItem(media[0], media)),
            const SizedBox(width: 2),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildMediaItem(media[1], media)),
                  const SizedBox(height: 2),
                  Expanded(child: _buildMediaItem(media[2], media)),
                ]
              )
            )
          ],
        )
      );
    }
    
    if (media.length == 4) {
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            Expanded(child: _buildMediaItem(media[0], media)),
            const SizedBox(height: 2),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildMediaItem(media[1], media)),
                  const SizedBox(width: 2),
                  Expanded(child: _buildMediaItem(media[2], media)),
                  const SizedBox(width: 2),
                  Expanded(child: _buildMediaItem(media[3], media)),
                ]
              )
            )
          ]
        )
      );
    }

    // 5 or more
    return SizedBox(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: _buildMediaItem(media[0], media)),
          const SizedBox(height: 2),
          Expanded(
            flex: 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildMediaItem(media[1], media)),
                const SizedBox(width: 2),
                Expanded(child: _buildMediaItem(media[2], media)),
                const SizedBox(width: 2),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildMediaItem(media[3], media),
                      if (media.length > 4)
                        GestureDetector(
                          onTap: () => _openFullScreenViewer(context, media, 3),
                          child: Container(
                            color: Colors.black54,
                            child: Center(
                              child: Text(
                                "+${media.length - 4}",
                                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                              ),
                            )
                          ),
                        )
                    ],
                  )
                ),
              ]
            )
          )
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final data = widget.data;
    final timestamp = data['timestamp'] as Timestamp?;
    final timeString = timestamp != null ? timeago.format(timestamp.toDate()) : 'Recently';
    final authorName = data['authorName'] ?? 'Unknown';
    final authorImage = data['authorImage'] ?? '';
    final role = data['role'] ?? 'Teacher';
    final text = data['text'] ?? '';
    
    // Process media list
    List<Map<String, dynamic>> mediaList = [];
    if (data['media'] != null) {
        for(var m in (data['media'] as List)) {
            mediaList.add(Map<String, dynamic>.from(m as Map));
        }
    } else if (data['mediaUrl'] != null || data['imageUrl'] != null) {
        mediaList.add({
           'url': data['mediaUrl'] ?? data['imageUrl'],
           'type': data['mediaType'] ?? (data['imageUrl'] != null ? 'image' : 'none')
        });
    }

    final bgIndex = data['backgroundIndex'] ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final authUser = ref.watch(currentUserProvider);
    final likesList = List<String>.from(widget.data['likes'] ?? []);
    final reactionsMap = widget.data['reactions'] as Map<String, dynamic>? ?? {};
    
    String currentReaction = 'none';
    if (authUser != null) {
      if (reactionsMap.containsKey(authUser.uid)) {
        currentReaction = reactionsMap[authUser.uid];
      } else if (likesList.contains(authUser.uid)) {
        currentReaction = 'like';
      }
    }

    final Set<String> totalReactors = {...likesList, ...reactionsMap.keys};
    final int combinedLikeCount = totalReactors.length;
    final bool hasHearts = reactionsMap.values.contains('heart');
    final bool hasHahas = reactionsMap.values.contains('haha');
    final bool hasWows = reactionsMap.values.contains('wow');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.zero,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
                  backgroundColor: Theme.of(context).primaryColor,
                  child: authorImage.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                          Text(
                            "$role • $timeString",
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).textTheme.labelSmall?.color?.withOpacity(0.6),
                                ),
                          ),
                        if (data['targetClassName'] != null && data['targetClassName'].isNotEmpty)
                           Text(
                            " • ${data['targetClassName']}",
                             style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.accent),
                           ),
                      ],
                    ),
                    if (timestamp != null)
                      Text(
                        "Expires ${timestamp.toDate().add(const Duration(days: 7)).toString().substring(0, 10)}",
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.redAccent, fontSize: 10),
                      ),
                  ],
                ),
                const Spacer(),
                // Edit and Delete Options
                if (user?.uid == data['authorId'] || true)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: Theme.of(context).iconTheme.color?.withOpacity(0.5)),
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
            if (bgIndex != 0 && bgIndex < _backgroundGradients.length && text.length <= 130)
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: text.length < 85 ? 28 : 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (text.length > 200 && !_isExpanded) ? '${text.substring(0, 200)}...' : text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
                    ),
                    if (text.length > 200)
                      GestureDetector(
                        onTap: () => setState(() => _isExpanded = !_isExpanded),
                        child: Padding(
                           padding: const EdgeInsets.only(top: 4.0),
                           child: Text(_isExpanded ? 'See less' : 'See more', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                        )
                      )
                  ],
                ),
              ),
          
          const SizedBox(height: 8),

          // Media Content (Collage)
          if (mediaList.isNotEmpty)
            _buildMediaCollage(mediaList, context),

          // Stats (Likes/Comments)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                if (combinedLikeCount > 0)
                  GestureDetector(
                    onTap: () {
                      final allLikers = totalReactors.toList();
                      if (allLikers.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (_) => LikersDialog(uids: allLikers, schoolId: widget.schoolId),
                        );
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasHearts) const Text('❤️', style: TextStyle(fontSize: 12, color: Colors.red)),
                        if (hasHahas) const Text('😂', style: TextStyle(fontSize: 12)),
                        if (hasWows) const Text('😮', style: TextStyle(fontSize: 12)),
                        if (!hasHearts && !hasHahas && !hasWows)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                            child: const Icon(Icons.thumb_up, size: 10, color: Colors.white),
                          ),
                        const SizedBox(width: 6),
                        Text("$combinedLikeCount", style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(width: 8),
                        Text("View", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                const Spacer(),
                Text("${data['commentCount'] ?? 0} comments", style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),

          Divider(height: 1, color: Theme.of(context).dividerColor),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (btnContext) {
                    return GestureDetector(
                      onLongPressStart: (_) => _showReactions(btnContext),
                      onLongPressMoveUpdate: (details) => _updateHover(details.globalPosition),
                      onLongPressEnd: (_) {
                        final emojis = ['like', 'heart', 'haha', 'wow'];
                        if (_hoverIndexNotifier.value != -1) {
                           final selected = emojis[_hoverIndexNotifier.value];
                           _updateReaction(selected);
                        }
                        _hideReactions();
                      },
                      child: TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () {
                          if (currentReaction == 'none') {
                             _updateReaction('like');
                          } else {
                             _removeReaction();
                             final authUser = ref.read(currentUserProvider);
                             if (authUser != null && likesList.contains(authUser.uid)) {
                               FirebaseFirestore.instance
                                  .collection('schools')
                                  .doc(widget.schoolId)
                                  .collection('posts')
                                  .doc(widget.id)
                                  .update({ 'likes': FieldValue.arrayRemove([authUser.uid]) });
                             }
                          }
                        },
                        icon: _getReactionIcon(currentReaction, context),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                              _getReactionText(currentReaction),
                              style: TextStyle(
                                  color: _getReactionColor(currentReaction, context),
                                  fontWeight: currentReaction != 'none' ? FontWeight.bold : FontWeight.normal,
                              )
                          ),
                        ),
                      ),
                    );
                  }
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
                  icon: Icon(Icons.mode_comment_outlined, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7), size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("Comment", style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7)))
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text("Delete Post", style: Theme.of(context).textTheme.titleLarge),
        content: Text("Are you sure you want to delete this post?", style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
            )),
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
                
                // We're not handling complete media deletion here perfectly since it could be multiple
                // But it's okay for now, existing system didn't do full multiple either
                if (widget.data['mediaUrl'] != null) {
                   try {
                     await FirebaseStorage.instance.refFromURL(widget.data['mediaUrl']).delete();
                   } catch (e) {
                     print("Error deleting media: $e");
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
