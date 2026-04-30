import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/widgets/news_post_card.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/screens/create_post_screen.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  String? schoolId;
  String? schoolName;
  String? schoolLogo;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSchoolInfo();
  }

  Future<QuerySnapshot>? _postsFuture;

  void _refreshPosts() {
    if (schoolId != null) {
      setState(() {
        _postsFuture = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .get();
      });
    }
  }

  Future<void> _handleRefresh() async {
    _refreshPosts();
    if (_postsFuture != null) {
      await _postsFuture;
    }
  }

  Future<void> _fetchSchoolInfo() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        setState(() {
          _errorMessage = "User not logged in";
          _isLoading = false;
        });
        return;
      }

      print("🔍 [NewsFeed] Fetching school info for user: ${user.uid}");

      // Get correct schoolId from teacher data
      final teacherDataAsync = ref.read(teacherDataProvider);
      final teacherData = teacherDataAsync.value;

      if (teacherData == null || !teacherData.containsKey('schoolId')) {
        setState(() {
          _errorMessage = "School not assigned";
          _isLoading = false;
        });
        print("⚠️ [NewsFeed] Teacher data has no schoolId");
        return;
      }

      final teacherSchoolId = teacherData['schoolId'] as String;

      // Fetch the specific school's details
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(teacherSchoolId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (schoolDoc.exists) {
        setState(() {
          schoolId = schoolDoc.id;
          schoolName = schoolDoc.data()?['name'] ?? "School Feed";
          schoolLogo = schoolDoc.data()?['logo'] ?? schoolDoc.data()?['profileImage'];
          _errorMessage = null;
        });
        print("✅ [NewsFeed] Found school: ${schoolDoc.id}");
        _refreshPosts();
        _markFeedAsRead(); // Mark feed as read right after getting school info
      } else {
        setState(() {
          _errorMessage = "School not found";
        });
        print("⚠️ [NewsFeed] School document not found: $teacherSchoolId");
      }
    } catch (e) {
      print("💥 [NewsFeed] Error: $e");
      setState(() {
        _errorMessage = "Failed to load school info: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markFeedAsRead() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null || schoolId == null) return;

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(user.uid)
          .set({
        'lastReadNewsFeed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print("✅ [NewsFeed] Marked feed as read");
    } catch (e) {
      print("💥 [NewsFeed] Error marking feed as read: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
                  ],
                ),
              ),
              // expandedHeight: 120.0,
              floating: true,
              pinned: true,
              elevation: 4,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  if (schoolLogo != null)
                    CircleAvatar(
                      backgroundImage: NetworkImage(schoolLogo!),
                      radius: 16,
                    )
                  else
                    const Icon(Icons.shield, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "SchoolBook",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                        letterSpacing: -1.5,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              centerTitle: false,
            ),
          ];
        },
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.orange, size: 48),
                        const SizedBox(height: 16),
                        Text(_errorMessage!, style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchSchoolInfo,
                          child: const Text("Retry"),
                        )
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _handleRefresh,
                    child: FutureBuilder<QuerySnapshot>(
                    future: _postsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}', style: Theme.of(context).textTheme.bodyMedium));
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data?.docs ?? [];

                      if (docs.isEmpty) {
                        return ListView(
                          children: [
                            _buildCreatePostTrigger(context),
                            SizedBox(
                              height: 300,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.feed_outlined, size: 64, color: Theme.of(context).iconTheme.color?.withOpacity(0.5)),
                                    const SizedBox(height: 16),
                                    Text(
                                      "No posts yet",
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: docs.length + 1, // +1 for Create Post
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildCreatePostTrigger(context);
                          }
                          final data = docs[index - 1].data() as Map<String, dynamic>;
                          final id = docs[index - 1].id;
                          return NewsPostCard(
                            id: id,
                            data: data,
                            schoolId: schoolId!,
                          );
                        },
                      );
                    },
                  ),
                ),
      ),
    );
  }

  Widget _buildCreatePostTrigger(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final teacherDataAsync = ref.watch(teacherDataProvider);
    final teacherData = teacherDataAsync.value;
    
    final teacherName = teacherData?['name'] ?? user?.displayName ?? 'Teacher';
    final role = teacherData?['role'] ?? 'Teacher';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.zero,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: user?.photoURL != null 
                    ? NetworkImage(user!.photoURL!) 
                    : null,
                radius: 20,
                child: user?.photoURL == null 
                    ? const Icon(Icons.person) 
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teacherName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      role,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (schoolId != null) {
                       Navigator.push(
                         context,
                         MaterialPageRoute(builder: (_) => CreatePostScreen(schoolId: schoolId!)),
                       );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                    ),
                    child: Text(
                      "Write a post...",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.image, color: Colors.green),
                onPressed: () {
                     if (schoolId != null) {
                       Navigator.push(
                         context,
                         MaterialPageRoute(builder: (_) => CreatePostScreen(schoolId: schoolId!)),
                       );
                    }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
